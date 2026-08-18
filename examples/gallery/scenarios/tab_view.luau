--!strict
--[[ Scenario 'tab_view' — TWO BARS, AND NEITHER ONE IS THE OTHER'S
	(navigation-and-menus D5; reference `r2-top-tab-bar.mov`).

	`r2` is one screen with two tab strips on it: a page's own top bar living
	inside a screen that is itself a tab of the app-level bottom bar. That shape
	is the whole reason `newTabView` is a construct rather than a picker
	property, and every claim it makes is invisible in a still frame:

	  · THE PLACEMENTS. On a phone the app bar takes the thumb zone and the
	    page's bar takes the top — and the rule that makes that true is that an
	    INNER TabView never reads `adaptive.navPlacement`. If it did, both bars
	    would answer `bottomBar` and the page's would be painted over the app's.
	    The two bars would still be on screen; they would just be in the same
	    place. So both levels PRINT the placement they resolved and which
	    authority answered it — `policy` for the outer, `nested` for the inner.
	  · THE EVICTION. Switching a tab is a real disposal, and a real disposal and
	    a hidden subtree paint the same picture. So every tab counts its own
	    BUILDS: leave a tab, come back, and its number goes up. That is the
	    accepted cost of the ruling, on screen, rather than a line in a document
	    somebody has to take on faith.
	  · THE ESCAPE HATCH, which is ownership and not a flag. The Notes tab holds
	    two counters that are identical to look at and are owned by different
	    scopes: one by the tab, one by this screen. Switch away and back — the
	    tab's is zero and the screen's is exactly where it was left. That is the
	    whole of the documented answer for state that must survive a switch.
	  · THE STRIP IS NEVER EVICTED, which is what makes a badge worth having.
	    Inbox carries an unread count and it keeps counting while its own content
	    does not exist; the "+1 unread" button is on the OTHER tabs.

	THE OVERFLOW IS THE PAGE BAR. Eight destinations at a phone width measure
	wider than the band, so a hugging strip sits in a horizontal ScrollView and
	the selected tab is brought into view. A tap already scrolls it, and so does
	a keyboard or pad move (the presenter reveals every focus move) — the case
	that needed the construct's own handling is a selection change that moved no
	focus at all, which is what the two Jump chips do.

	TWO SKINS, ONE MECHANISM: the app bar wears the `underline` every reference
	tab strip draws, the page bar wears the `pill` a segmented control does. Both
	are D4's sliding indicator and both slide.

	TWO HOSTS MOUNT THIS FILE and only one runs steps: the scenario runner drives
	`steps` by name, and the showcase demo picker mounts it with a minimal ctx
	and no step ever runs. Every affordance is an ordinary control with its own
	callback, so a player can drive the whole thing by hand.
]]

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy` — the
	contract `surface_overlap.luau` and `flow_wrap.luau` carry, because the
	gallery spec's localization case re-runs the fixture through a ~1.4x
	pseudo-localizing expansion and a check that cannot reach the strings cannot
	make that claim. Flat keys only. ]]
local COPY = {
	title = "Two bars, and neither one is the other's",
	appBar = "App bar: ",
	pageBar = "Page bar: ",
	builds = "Builds: ",
	lifecycle = "Lifecycle: ",
	-- the four app-level destinations
	pages = "Pages",
	inbox = "Inbox",
	notes = "Notes",
	me = "Profile",
	-- the eight page-level destinations, which is `f1`'s own strip
	avatars = "Avatars",
	body = "Body",
	clothing = "Clothing",
	accessories = "Accessories",
	backgrounds = "Backgrounds",
	emotes = "Emotes",
	bundles = "Bundles",
	favorites = "Favorites",
	nestedNote = "The page bar is INSIDE the app bar's content, so it never asks the placement policy — that is the only reason two bars are not drawn in one home.",
	jumpLast = "Jump to the last page",
	jumpFirst = "Jump to the first page",
	jumpNote = "A jump moves the selection without moving focus, which is the one reveal the construct handles itself.",
	unreadTitle = "The strip is never evicted",
	unreadNote = "This tab's content is torn down every time you leave it. Its badge is not: the count below keeps climbing from the other tabs, because a badge on an unselected tab is the whole point of a badge.",
	bumpUnread = "+1 unread",
	clearUnread = "Mark all read",
	keptTitle = "The escape hatch is ownership, not a flag",
	keptNote = "Both counters below are the same control. The first is owned by this screen and outlives every switch; the second is owned by the tab scope this factory was handed and dies with it. Leave this tab and come back.",
	kept = "Kept outside the TabView: ",
	tabOwned = "Owned by this tab's scope: ",
	bump = "Count one",
	builtHere = "This page has been built ",
	times = " time(s) since the demo opened.",
	meTitle = "A tab is a page, not a value",
	meNote = "A segmented picker chooses a value and keeps every option's meaning on screen. A tab view chooses a page, and the pages it is not showing do not exist.",
	pagesNote = "Eight destinations, a phone-width band: the strip hugs its content, scrolls, and brings the selected one into view.",
}

local APP_TABS = { "pages", "inbox", "notes", "me" }
local PAGE_TABS = { "avatars", "body", "clothing", "accessories", "backgrounds", "emotes", "bundles", "favorites" }

return {
	title = "Tabs, nested",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("tab-view-scenario")
		-- thirteen memos, owned, so a demo swap does not leave them behind
		local conditions = Facet.adaptive.conditions(core, ctx.env, { scope = scope })

		--[[ THE TWO SELECTIONS, AND THEY ARE TWO. `selection` is the caller's
			Signal by contract, so the app level and the page level are owned by two
			different signals here and neither construct can see the other's — which
			is what lets the page keep its place while the app switches away and
			back. ]]
		local section = scope:own(core:signal("pages"))
		local page = scope:own(core:signal("avatars"))

		-- the badge, which is the one piece of tab state that is NEVER torn down
		local unread = scope:own(core:signal(3))
		-- ...and the two counters the Notes tab compares. This one is owned HERE.
		local kept = scope:own(core:signal(0))
		-- what the tab-owned counter last read, published so a step can see it
		local tabOwnedNow = scope:own(core:signal(0))
		--[[ …and the tab's own press, held here only while that tab EXISTS. The
			runner's step and the on-screen chip have to be the same press or the step
			would prove something the player cannot do; and when the tab is evicted
			this goes back to nil, which is the eviction stated one more way. ]]
		local tabBump: (() -> ())? = nil

		--[[ THE BUILD COUNTERS — this fixture's whole subject. A plain table
			counted from inside each content factory (the only place that knows a
			subtree was made) beside one Signal that puts the numbers on screen, which
			is `virtual_grid`'s instrument for the same class of claim: laziness and
			eviction are both COUNTS, and a mounted-node count cannot see either. ]]
		local builds: { [string]: number } = {}
		local buildLine = scope:own(core:signal(""))
		local lifecycleLine = scope:own(core:signal(""))
		local outer: any = nil
		local inner: any = nil

		local function buildText(): string
			local parts: { string } = {}
			for _, id in APP_TABS do
				table.insert(parts, `{COPY[id]} {builds[id] or 0}`)
			end
			local pageParts: { string } = {}
			for _, id in PAGE_TABS do
				if (builds[id] or 0) > 0 then
					table.insert(pageParts, `{COPY[id]} {builds[id]}`)
				end
			end
			local line = COPY.builds .. table.concat(parts, " · ")
			if #pageParts > 0 then
				line ..= "\n" .. COPY.pageBar .. table.concat(pageParts, " · ")
			end
			return line
		end

		--[[ THE LIFECYCLE LINE reads the construct's own dump rather than counting
			anything itself, so the fixture's numbers and the framework's can be
			compared instead of agreeing by construction. `contentMounts` climbing
			while `contentEvictions` stayed put is exactly what a leak looks like.

			IT IS WRITTEN ONLY WHEN IT CHANGED, which is what lets the tick below
			drive it: an unconditional `:set` of an identical string would repaint,
			re-solve and re-enter this function every frame forever. ]]
		local function put(signal: any, value: string)
			if signal:get() ~= value then
				signal:set(value)
			end
		end
		local function readState()
			put(buildLine, buildText())
			if outer == nil then
				return
			end
			local d = outer.dump()
			local line = `mounts {d.contentMounts} · evictions {d.contentEvictions} · live [{table.concat(
				d.mountedTabs,
				", "
			)}] · reveals {d.reveals}`
			if inner ~= nil then
				local i = inner.dump()
				line ..= `\npage: mounts {i.contentMounts} · evictions {i.contentEvictions} · reveals {i.reveals}`
			end
			put(lifecycleLine, COPY.lifecycle .. line)
		end

		local function noteBuild(id: string)
			builds[id] = (builds[id] or 0) + 1
			readState()
		end

		local function placementLine(prefix: string, control: any): any
			return core:memo(function(use)
				local resolved = use(control.placement)
				return `{prefix}{resolved} ({control.dump().placementSource})`
			end)
		end

		local function chip(id: string, label: any, onPress: () -> ()): any
			return UI.Button({
				id = id,
				label = label,
				surface = "chip",
				onActivate = function()
					onPress()
					readState()
				end,
			})
		end

		local function panel(id: string, children: { any }): any
			return UI.VStack({
				id = id,
				surface = "control",
				padding = "s",
				gap = "xs",
				width = { type = "fill", weight = 1 },
				children = children,
			})
		end

		--[[ THE STATUS PANEL RIDES INSIDE EVERY TAB, AND THAT IS A MEASUREMENT
			RATHER THAN A PREFERENCE. It stood above the TabView first, as a fixed
			band, and the overflow sweep filed 114 findings for it: four lines of prose
			at the +14 text preference under a ~1.4x localization measure taller than a
			359x718 phone has to spare, so the band took the height and the construct
			underneath it was arranged into a 0px box. Its own numbers then reported
			nothing, on the surface whose entire job is to report them.

			Inside a tab's scroller the same four lines cost nothing at any preference,
			and the readout is no worse for it: exactly one tab is ever mounted, so it
			is on screen either way. It is REBUILT with its tab, which is the fixture's
			own subject happening to its own instrument. ]]
		local function statusPanel(id: string, appLine: any?): any
			local rows: { any } = { UI.Text({ id = "Title", text = COPY.title, textSize = "body" }) }
			-- the page tabs pass nil: their own Placements panel already carries the
			-- app's answer beside the page's, which is where the comparison belongs
			if appLine ~= nil then
				table.insert(rows, UI.Text({ id = "AppPlacement", text = appLine, textSize = "caption" }))
			end
			table.insert(rows, UI.Text({ id = "Builds", text = buildLine, textSize = "caption", role = "secondary" }))
			table.insert(
				rows,
				UI.Text({ id = "Lifecycle", text = lifecycleLine, textSize = "caption", role = "secondary" })
			)
			return panel(id, rows)
		end

		--[[ THE PAGE LEVEL — `r2`'s own top bar, and it is built INSIDE the app
			tab's content factory. That is not a stylistic choice: `content` is a
			factory the construct invokes, so a TabView constructed during that
			invocation IS inner, and the framework decides it from where the call
			happens rather than from a flag the caller could get wrong. ]]
		local function pageTabs(): { any }
			local out: { any } = {}
			for _, id in PAGE_TABS do
				table.insert(out, {
					id = id,
					label = COPY[id],
					content = function(pageScope: any)
						noteBuild(id)
						--[[ THE TWO PLACEMENT LINES LIVE ON THE PAGE, NOT ABOVE THE BAR,
							and that was measured rather than chosen: a 320px-TALL landscape
							has room for the app's readout, one band, one bar and a page — and
							three text blocks between the bar and the page overflowed the page
							body by 15px and the inner root by 46 at that viewport. Inside this
							scroller they cost nothing, and they are still exactly where the
							comparison wants them: the two answers next to each other, on the
							page whose own bar is the second one.

							They are owned by the PAGE scope, so they die with this tab — which
							they must, because the control the inner one reads does. ]]
						local outerLine = pageScope:own(placementLine(COPY.appBar, outer))
						local innerLine = pageScope:own(placementLine(COPY.pageBar, inner))
						return UI.ScrollView({
							id = "PageBody",
							axis = "y",
							gap = "xs",
							width = { type = "fill", weight = 1 },
							height = { type = "fill", weight = 1 },
							children = {
								statusPanel("Status"),
								UI.Text({ id = "Name", text = COPY[id], textSize = "heading" }),
								UI.Text({
									id = "Built",
									text = `{COPY.builtHere}{builds[id] or 0}{COPY.times}`,
									textSize = "caption",
									role = "secondary",
								}),
								panel("Placements", {
									UI.Text({ id = "Outer", text = outerLine, textSize = "caption" }),
									UI.Text({ id = "Inner", text = innerLine, textSize = "caption" }),
									UI.Text({
										id = "Why",
										text = COPY.nestedNote,
										textSize = "caption",
										role = "secondary",
									}),
								}),
								UI.HStack({
									id = "Jumps",
									gap = "xs",
									wrap = true,
									width = { type = "fill", weight = 1 },
									children = {
										chip("JumpLast", COPY.jumpLast, function()
											page:set(PAGE_TABS[#PAGE_TABS])
										end),
										chip("JumpFirst", COPY.jumpFirst, function()
											page:set(PAGE_TABS[1])
										end),
									},
								}),
								UI.Text({
									id = "JumpNote",
									text = COPY.jumpNote,
									textSize = "caption",
									role = "secondary",
								}),
								UI.Text({
									id = "Note",
									text = COPY.pagesNote,
									textSize = "caption",
									role = "secondary",
								}),
							},
						})
					end,
				})
			end
			return out
		end

		local function pagesBody(tabScope: any): any
			--[[ `sizing = "hug"` IS THE OVERFLOW, DECLARED. A `fill` strip divides
				its offer among its tabs and therefore cannot overflow — eight tabs at
				320px would be 40px each — so an autoscroll demonstration built on the
				filling default would demonstrate nothing. A `topBar` already hugs; it is
				written out here because this fixture's subject is what hugging costs. ]]
			inner = Facet.Controls.TabView(core, {
				id = "Page",
				selection = page,
				indicator = "pill",
				sizing = "hug",
				env = ctx.env,
				tabs = pageTabs(),
				onChange = function()
					readState()
				end,
			})
			tabScope:own(inner)
			tabScope:own(function()
				inner = nil
			end)
			--[[ THE APP TAB'S WHOLE BODY IS THE PAGE-LEVEL TabView, with nothing
				between the two bars. Everything this fixture has to SAY about the pair
				lives one level down, inside the page's own scroller — see the note in
				`pageTabs`. A band between them cost a 320px-tall landscape more height
				than it had. ]]
			return inner.blueprint
		end

		local function inboxBody(tabScope: any): any
			return UI.ScrollView({
				id = "InboxBody",
				axis = "y",
				gap = "xs",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					statusPanel("Status", tabScope:own(placementLine(COPY.appBar, outer))),
					UI.Text({ id = "Title", text = COPY.unreadTitle, textSize = "heading" }),
					UI.Text({ id = "Note", text = COPY.unreadNote, textSize = "caption", role = "secondary" }),
					UI.Text({
						id = "Count",
						text = core:memo(function(use)
							return `{COPY.inbox}: {use(unread)}`
						end),
						textSize = "body",
					}),
					chip("ClearUnread", COPY.clearUnread, function()
						unread:set(0)
					end),
				},
			})
		end

		local function notesBody(tabScope: any): any
			--[[ THE TWO COUNTERS, AND THE ONLY DIFFERENCE BETWEEN THEM IS WHO OWNS
				THEM. `kept` was created on this screen's scope, above; `tabOwned` is
				created here, on the scope this factory was handed, which the framework
				disposes the moment the tab is left. There is deliberately no `retain`
				flag — ownership already answers the question, and this is that answer
				with two numbers on it. ]]
			local tabOwned = tabScope:own(core:signal(0))
			tabOwnedNow:set(0)
			local function bumpBoth()
				kept:set(kept:get() + 1)
				tabOwned:set(tabOwned:get() + 1)
				tabOwnedNow:set(tabOwned:get())
			end
			tabBump = bumpBoth
			tabScope:own(function()
				tabBump = nil
				tabOwnedNow:set(0)
			end)
			return UI.ScrollView({
				id = "NotesBody",
				axis = "y",
				gap = "xs",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					statusPanel("Status", tabScope:own(placementLine(COPY.appBar, outer))),
					UI.Text({ id = "Title", text = COPY.keptTitle, textSize = "heading" }),
					UI.Text({ id = "Note", text = COPY.keptNote, textSize = "caption", role = "secondary" }),
					UI.Text({
						id = "Kept",
						text = core:memo(function(use)
							return COPY.kept .. tostring(use(kept))
						end),
						textSize = "body",
					}),
					UI.Text({
						id = "Owned",
						text = tabScope:own(core:memo(function(use)
							return COPY.tabOwned .. tostring(use(tabOwned))
						end)),
						textSize = "body",
					}),
					UI.HStack({
						id = "Bumps",
						gap = "xs",
						wrap = true,
						width = { type = "fill", weight = 1 },
						children = {
							chip("Bump", COPY.bump, bumpBoth),
							chip("BumpUnread", COPY.bumpUnread, function()
								unread:set(unread:get() + 1)
							end),
						},
					}),
				},
			})
		end

		local function meBody(tabScope: any): any
			return UI.ScrollView({
				id = "MeBody",
				axis = "y",
				gap = "xs",
				width = { type = "fill", weight = 1 },
				height = { type = "fill", weight = 1 },
				children = {
					statusPanel("Status", tabScope:own(placementLine(COPY.appBar, outer))),
					UI.Text({ id = "Title", text = COPY.meTitle, textSize = "heading" }),
					UI.Text({ id = "Note", text = COPY.meNote, textSize = "caption", role = "secondary" }),
					chip("BumpUnreadMe", COPY.bumpUnread, function()
						unread:set(unread:get() + 1)
					end),
				},
			})
		end

		local BODIES: { [string]: (any) -> any } = {
			pages = pagesBody,
			inbox = inboxBody,
			notes = notesBody,
			me = meBody,
		}

		local appTabs: { any } = {}
		for _, id in APP_TABS do
			table.insert(appTabs, {
				id = id,
				label = COPY[id],
				-- the count seal rides the OPTION, so it is part of the strip and the
				-- strip is what never gets torn down
				badge = if id == "inbox"
					then scope:own(core:memo(function(use)
						local n = use(unread)
						return if n > 0 then tostring(n) else ""
					end))
					else nil,
				content = function(tabScope: any)
					noteBuild(id)
					return BODIES[id](tabScope)
				end,
			})
		end

		--[[ THE APP LEVEL. `placement = "automatic"` is the default and is written
			out because it is the thing being demonstrated: the policy reads space and
			input, never a device name, and publishes its answer as a Readable so this
			screen can print it rather than re-deriving the rule. ]]
		outer = Facet.Controls.TabView(core, {
			id = "App",
			selection = section,
			placement = "automatic",
			indicator = "underline",
			conditions = conditions,
			env = ctx.env,
			tabs = appTabs,
			onChange = function()
				readState()
			end,
		})
		scope:own(outer)

		readState()

		--[[ AND THE ONE SEAM THAT MAKES THE COUNTS TRUE RATHER THAN NEARLY TRUE.
			`contentMounts` is incremented by the construct AFTER it invokes the
			caller's factory, so a number read from inside that factory is always one
			behind — the first paint of this fixture reported `mounts 0` for a page
			bar that had just been built. Nothing the caller can subscribe to fires
			between those two statements, so the readout re-reads on the presenter's
			own tick, and `put` above is what makes that free: a frame in which
			nothing moved writes nothing, repaints nothing and re-solves nothing. ]]
		if ctx.presenter ~= nil and ctx.presenter.onTick ~= nil then
			scope:own(ctx.presenter.onTick(function()
				readState()
			end))
		end

		--[[ THE SCREEN IS THE CONSTRUCT, with nothing above it. Every readout this
			fixture has rides inside a tab (see `statusPanel`) rather than in a band of
			its own, because a band of prose over a TabView is a band that takes the
			height at a raised text preference and leaves the thing it is describing
			arranged into nothing. ]]
		local screen = UI.Screen({
			id = "TabViewDemo",
			-- NO PAGE PADDING. A tab bar is chrome that belongs against its own edge
			-- — every reference shell places one edge-to-edge — and on a 320px-tall
			-- landscape carrying TWO of them the eight pixels are the difference
			-- between the page fitting and not.
			children = {
				UI.VStack({
					id = "Root",
					gap = "xs",
					align = "stretch",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = { outer.blueprint },
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			section = section,
			page = page,
			unread = unread,
			kept = kept,

			steps = {
				select = function(_built: any, payload: string?)
					section:set(payload or "inbox")
					readState()
					return { section = section:get(), dump = outer.dump() }
				end,
				selectPage = function(_built: any, payload: string?)
					page:set(payload or PAGE_TABS[#PAGE_TABS])
					readState()
					return { page = page:get(), reveals = if inner ~= nil then inner.dump().reveals else nil }
				end,
				-- the step IS the chip: a step that wrote the signals itself would
				-- prove a press no player can make
				bump = function()
					if tabBump ~= nil then
						(tabBump :: () -> ())()
					else
						kept:set(kept:get() + 1)
					end
					readState()
					return { kept = kept:get(), tabOwned = tabOwnedNow:get(), onTab = tabBump ~= nil }
				end,
				bumpUnread = function()
					unread:set(unread:get() + 1)
					readState()
					return { unread = unread:get() }
				end,
				reread = function()
					readState()
					return { builds = buildLine:get(), lifecycle = lifecycleLine:get() }
				end,
			},

			report = function()
				return {
					app = outer.dump(),
					page = if inner ~= nil then inner.dump() else nil,
					builds = table.clone(builds),
					kept = kept:get(),
					tabOwned = tabOwnedNow:get(),
					unread = unread:get(),
				}
			end,

			dispose = function()
				-- the app-level control is owned by the scope above, so this is one
				-- teardown rather than two: a second `outer.dispose()` here would be a
				-- resource with two owners, which is the one thing §6.3 refuses
				scope:dispose()
			end,
		}
	end,
}
