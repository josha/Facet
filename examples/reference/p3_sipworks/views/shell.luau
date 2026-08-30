--!strict
-- The Sipworks shell (spec §5): a nav whose home is a POLICY, and the two panes
-- behind it. Since framework-gaps-phase2 §6 the nav itself is one construct —
-- `Facet.Controls.TabView` — and this file is what an app still owns around it.
--
-- THREE DEVIATIONS FROM THE SPEC'S LETTER, each preserving what §5 is about:
--
--  1. The spec gives the Nav region TWO ranked forms (sidebar, then tab row)
--     chosen by a `UI.Composition`. A Region's forms are chosen by FAILURE — a
--     region steps down when its arrangement cannot fit — not by width, so a
--     phone would have got a vertical sidebar across the bottom of the screen.
--     The home is therefore `adaptive.navPlacement`, which answers from shape and
--     input facts, and the construct is what mounts it.
--
--  2. Declaration order is the same in every home (Menu, Favorites, Blend Book,
--     Steam Stamps) rather than moving the Stamps pocket to the foot in one and
--     the third slot in the other. The framework states the reason: "Focus order
--     is the declaration's own order, and is therefore identical in every
--     arrangement" — so two orders would have been one order and a lie.
--
--  3. THE STAMPS POCKET NO LONGER SITS AT THE RAIL'S FOOT (§6, recorded in
--     ADR-0045). A spacer used to push it there, and a spacer inside the strip is
--     not something an accessory slot can express: the pocket is a nav DESTINATION
--     whose home moves, not chrome beside the tabs, and one picker object serves
--     every placement by contract. It reads in its declared order instead. What it
--     DOES on a roomy shape is unchanged — it presents the rewards card rather
--     than swapping the section (`commands.selectSection`), which is why the
--     construct's own write is reconciled below.

local dims = require("../content/dims")
local listView = require("./list")
local detailView = require("./detail")
local bookView = require("./book")
local rewardsView = require("./rewards")
local taskView = require("./task")

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
-- navigation — ONE construct (framework-gaps-phase2 §6)
-- ---------------------------------------------------------------------------
--
-- THE FOUR NAV HOMES are still `adaptive.navPlacement`'s (director ruling
-- 2026-08-09, aligned to the platform tab-bar guidance the reference follows):
--
--   sidebar          desktop shape — the vertical rail, full labels
--   topBar           tablet/ten-foot shape — CENTER-ALIGNED, HUGS its tabs
--                    (never full width), search rides the band's trailing edge
--   bottomBar        phone portrait — full-width tabs in the thumb zone
--   bottomBarCompact phone landscape — the SAME bar in its reduced inline form
--                    (short labels, centred)
--
-- ...but this file no longer BUILDS them. `Facet.Controls.TabView` owns the
-- placement, the strip, the content region's lifecycle and the focus order, and
-- what kept this proof off it until §6 was the SEARCH FIELD's two chrome homes:
-- the top band's trailing edge and the strip directly above the thumb-zone dock.
-- Those are `accessories.trailing` and `accessories.aboveBar`, and the third
-- home — inline atop the list pane on the sidebar shape — was never chrome at
-- all: it lives in the CONTENT, where it always did.
--
-- THE SHORT VOCABULARY SURVIVES AS A BOUND LABEL rather than a second bar
-- (director refinement 2026-08-09: "consider when to use the compact
-- representation — I see a lot of cutoff text"). A thumb-zone home takes the
-- short localized string and the roomier homes take the full one; `Option.label`
-- is a Readable, so the flip follows a live rotation and a live locale change
-- alike, which a construction-time compact form could not.

-- ---------------------------------------------------------------------------
-- section bodies — one two-pane shape, one bound pane width
-- ---------------------------------------------------------------------------

local function paneWidth(app: any): any
	return app.own(app.core:memo(function(use)
		if not use(app.paneSplit) then
			return dims.fill
		end
		return dims.minMax("app.sip.listPaneMin", "app.sip.listPaneMin", "app.sip.listPaneMax")
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
		width = dims.fill,
		height = dims.fill,
		children = {
			UI.Divider({ id = "Rule" }),
			UI.ZStack({
				id = "PaneBody",
				width = dims.fill,
				height = dims.fill,
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

	--[[ THE TASK CARD SCROLLS WITH THE CATALOGUE IT IS ABOUT, which is the same
		home the Blend Book's unlock card already has and for the same reason: a
		card pinned above the list eats the list's whole height on a phone. It is
		the FIRST thing in the section, so the opening screen states the goal, the
		progress and the next action before the menu — and browsing past it is
		allowed, because the strip above the nav keeps the task on screen. ]]
	local leading: { any } = { taskView.card(app) }
	if kind == "recipes" then
		table.insert(leading, bookView.unlockCard(app))
	end

	local listBlueprint = listView.blendList(app, {
		id = "List",
		items = items,
		leading = UI.VStack({ id = "Lead", gap = "m", width = dims.fill, children = leading }),
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
				width = dims.fill,
				height = dims.fill,
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
								width = dims.fill,
								height = dims.fill,
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
		width = dims.fill,
		height = dims.fill,
		children = {
			UI.VStack({
				id = "ListPane",
				gap = "s",
				width = paneWidth(app),
				height = dims.fill,
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
		width = dims.fill,
		height = dims.percent(1),
		children = {
			-- the same task card the list sections lead with: the Stamps pocket is
			-- a section like any other and must not be the one place the task
			-- vanishes from
			taskView.card(app),
			UI.ZStack({
				-- HUGS, never fills: a `fill` height inside a y-scroller measures
				-- against a canvas that is itself derived from the content
				id = "Backdrop",
				width = dims.fill,
				alignH = "center",
				alignV = "start",
				children = {
					rewardsView.card(app, { id = "RewardsCard", compact = true }),
				},
			}),
		},
	})
end

--[[ ONE TAB'S CONTENT. The plate is the same `canvasGroup` the four `When`-gated
	section hosts each declared, and it is still the fade GROUP the enter
	transition needs — the transition just moved onto the construct, which is the
	one place that knows a section change IS a tab change now. The padding moved
	with it: `newTabView` deliberately declares no spacing of its own, so the
	breathing room a page wants belongs to the page. ]]
local function sectionContent(app: any, section: string): any
	local UI = app.UI
	return UI.ZStack({
		id = "Body",
		canvasGroup = true,
		padding = "s",
		width = dims.fill,
		height = dims.fill,
		children = {
			if section == "stamps" then stampsSection(app) else listSection(app, section),
		},
	})
end

-- ---------------------------------------------------------------------------
-- the shell itself
-- ---------------------------------------------------------------------------

function shell.build(app: any): any
	local UI = app.UI
	local core = app.core

	-- the placement policy — and, since GAP 7a (framework-gaps-phase2 §7)
	-- promoted the four homes onto `adaptive.conditions` itself, the inline
	-- search home reads its own promoted predicate rather than a memo this
	-- file built by hand
	app.navSidebar = app.cond.navSidebar
	-- the accessory (and the top band's trailing slot) only makes sense on the
	-- sections that HAVE a searchable list — never over the stamps pocket
	app.searchable = app.own(core:memo(function(use)
		return use(app.state.section) ~= "stamps"
	end))
	-- ...and the SHORT vocabulary's own condition: the two thumb-zone homes
	local terse = app.own(core:memo(function(use)
		return use(app.cond.navBottomBar) or use(app.cond.navBottomBarCompact)
	end))
	local function sectionLabel(section: string): any
		-- both memos are built ONCE and selected between: `app.text` mints a new
		-- one per call, so choosing the key inside a memo body would mint one per
		-- evaluation
		local full = app.text(SECTION_LABEL[section])
		local short = app.text(SECTION_LABEL[section] .. ".short")
		return app.own(core:memo(function(use)
			return if use(terse) then use(short) else use(full)
		end))
	end

	--[[ THE STRIP'S SELECTION IS A NAV INTENT; `state.section` stays the authority.
		Steam Stamps is a VERB on every roomy shape — it presents the rewards card
		rather than swapping the section — and a destination only on a compact one,
		and `commands.selectSection` is the single place that rule lives. The
		construct writes its own Signal on activation (as every picker does), so the
		intent is reconciled back to whatever the command actually did, in the same
		synchronous turn: a tab that declines to become the section snaps back before
		anything is solved. ]]
	local intent = app.own(core:signal(app.state.section:get()))
	-- `core:observe` hands back a DISCONNECT FUNCTION, not a disposable, so the
	-- proof's own `own` gets the shape it disposes
	local unmirror = core:observe(app.state.section, function(value: string)
		intent:set(value)
	end)
	app.own({ dispose = unmirror })

	local tabs: { any } = {}
	for _, section in SECTIONS do
		local this = section
		table.insert(tabs, {
			id = this,
			label = sectionLabel(this),
			content = function()
				return sectionContent(app, this)
			end,
		})
	end

	local nav = app.own(app.Facet.Controls.TabView(core, {
		id = "Nav",
		selection = intent,
		-- the conditions this proof already built, passed in rather than rebuilt:
		-- `adaptive.conditions` creates its own set of memos and two copies would be two
		-- answers to one question
		conditions = app.cond,
		env = app.env,
		--[[ THE RAIL'S BAND, and it is a MEASURED finding rather than a taste: a hug
			rail is as wide as its widest label, and at the 1.4x locale with the
			largest text preference that pushed this rail past 400px and squeezed the
			content lane — the two-pane row overflowed by 82px on a 1024px tablet.
			A rail is a rail: it states its band and the labels adapt inside it. ]]
		railWidth = dims.minMax("app.sip.navRailMin", "app.sip.navRailMin", "app.sip.navRailMax"),
		-- the enter fade the four section hosts each declared
		transition = { enter = "fade" },
		tabs = tabs,
		-- NO TRANSACTION HERE, deliberately: the control already wraps its own write
		-- and this callback in ONE turn (see `newPicker`), which is what makes the
		-- snap-back invisible. Spelling a second one would teach a ceremony the
		-- framework guarantees.
		onChange = function(id: string)
			app.commands.selectSection(id)
			intent:set(app.state.section:get())
		end,
		accessories = {
			--[[ THE TOP BAND'S TRAILING EDGE. The construct parks this at the band's
				end as an OVERLAY, so the hugging tab cluster underneath keeps its
				centre — which is the shape this proof drew by hand with a ZStack and
				an `align = "end"` wrapper, and the contract `newTabView` now owns. ]]
			trailing = function()
				return UI.When({
					id = "TopSearchWhen",
					condition = app.searchable,
					thenView = function()
						return UI.VStack({
							id = "TopSearchBox",
							width = dims.minMax(160, 200, 260),
							children = { listView.searchBar(app) },
						})
					end,
				})
			end,
			--[[ THE TAB-BAR ACCESSORY: the search field rides directly above the
				bottom tab bar (the guidance's accessory slot), for the sections that
				search. Both thumb-zone homes host it — the same bar in two forms is
				still one bar — which is exactly what the hand-built `Dock` said with
				a `bottomBar or bottomBarCompact` memo of its own. ]]
			aboveBar = function()
				return UI.When({
					id = "AccessoryWhen",
					condition = app.searchable,
					thenView = function()
						return UI.VStack({
							id = "Accessory",
							width = dims.fill,
							padding = "xs",
							children = { listView.searchBar(app) },
						})
					end,
				})
			end,
		},
	}))

	--[[ THE TASK BAND SITS ABOVE THE NAV, AND THAT IS THE WHOLE CHANGE OF SHAPE.

		The app used to open on the blend menu inside this construct — a catalogue,
		with the loop it is about ten orders away and nothing on screen saying so.
		The band states the goal, the progress and the next action, and the nav
		keeps everything it had underneath it: browsing, search, favourites, the
		Blend Book and the Steam Stamps pocket are all still one press away and
		none of them is required to finish the loop.

		THE STRIP IS ONE LINE BY CONSTRUCTION, never a fixed px height and never a
		paragraph: both of its texts declare `lineLimit = 1` with `disclose`, so it
		costs exactly one line box at every text preference and in both locales, and
		the construct's own `height = FILL` root takes everything else. The task's
		full copy — goal, next action, verb, completion — is the CARD, and the card
		rides inside the section's own scroller where it can be as tall as its
		words. `views/task.luau`'s header records the measurement that decided it. ]]
	return UI.Screen({
		id = "Sipworks",
		padding = 0,
		surface = "base",
		children = {
			UI.VStack({
				id = "Shell",
				gap = 0,
				width = dims.fill,
				height = dims.fill,
				children = { taskView.strip(app), nav.blueprint },
			}),
		},
	})
end

return shell
