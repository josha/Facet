--!strict
--[[ Scenario 'menu' — FIVE WAYS IN, AND ONE OF THEM HAS TO BE YOURS
	(navigation-and-menus D2; references `f1-avatar-editor.jpeg` and
	`r1-popup-list.mov`).

	`newMenu` is a list of VERBS, and the reason it is a construct rather than a
	popup with a different label is everything around the list: five gestures
	open it, two idioms present it, and a submenu behaves differently in each.
	None of that can be checked from a screenshot, and four of the five gestures
	cannot be synthesized in Studio at all — so this is the surface a person with
	a phone, a mouse and a pad in their hands drives by hand.

	THE FIVE ROUTES ARE FIVE SEPARATE CARDS, and the split is the framework's own
	authoring rule made visible rather than a layout choice. `newMenu` refuses a
	`triggers` set that drops `activate` unless it declares BOTH `keyboard` and
	`gamepad` — "a menu that only opens on right-click is a defect" — so the
	smallest set that isolates a gesture is not always one gesture:

	  · TAP        `{ activate }`             — the only route every input class has
	  · CHORD      `{ keyboard, gamepad }`    — the one card a tap does NOT open, on
	                                            purpose. That refusal is the test:
	                                            press it and nothing happens, then
	                                            press the context key
	  · RIGHT-CLICK `{ activate, secondary }` — a right-click is not an activate, so
	                                            a right-click that opens this proves
	                                            the secondary channel is wired
	  · HOLD       `{ activate, longPress }`  — it opens UNDER YOUR FINGER, at the
	                                            press rather than the release. If it
	                                            only appears when you let go, that
	                                            was the tap and long-press is dead

	WHAT THE READOUT CAN AND CANNOT SAY, stated on the screen as well as here,
	because a fixture that overstates its instrument is worse than no fixture:
	**the framework reports no open reason.** `onOpen` takes no argument and
	`dump().triggers` is the set that was DECLARED, not the one that fired. So the
	readout names the card that opened, the routes that card accepts, and the live
	interaction classes at that instant — which is exactly as far as the public
	surface goes today. It is enough to test every route, because each card
	accepts a different set and the tester knows which gesture they made.

	THE PRESENTATION IS FORCED FROM A CONTROL, NOT FROM A DEVICE. The idiom comes
	out of `menu_recipe.resolvePresentation(count, sizeClass, touchLive)` — a pure
	function of the item count, the space class and whether touch is a LIVE
	interaction class. So the Idiom picker below writes the ONE input that rule
	reads, and both idioms are reachable in one session on one machine:

	  · panel — each submenu level is its own surface anchored to its parent ROW,
	    and `surfaces` in the readout climbs with the chain;
	  · sheet — the touch idiom, where a submenu REPLACES the sheet's contents and
	    grows a Back row. `surfaces` stays 1 at any depth, which is the only way to
	    tell the two apart without looking.

	AND ONE CARD EXISTS FOR A REFUSAL: a menu whose every item is disabled still
	OPENS. Apple: "If all of a menu's items are unavailable, the menu itself needs
	to remain available so people can open it and learn about the commands it
	contains." A trigger that silently does nothing cannot be told from a dead
	button, which is why it gets a card of its own rather than a line in a doc.

	TWO HOSTS MOUNT THIS FILE and only one runs steps: the scenario runner drives
	`steps` by name, and the showcase demo picker mounts it with a minimal ctx and
	no step ever runs. Every affordance is an ordinary control with its own
	callback, so a player can drive the whole thing by hand.
]]

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy` — the
	contract `surface_overlap.luau` and `flow_wrap.luau` carry, because the
	gallery spec's localization case re-runs the fixture through a ~1.4x
	pseudo-localizing expansion and a check that cannot reach the strings cannot
	make that claim. Flat keys only. ]]
local COPY = {
	title = "Five ways into one list of verbs",
	intro = "Each card below opens the same avatar menu through a different gesture. The routes a card accepts are printed on it, because the framework reports no open reason — see the note at the bottom.",
	-- the four route cards
	tap = "Tap",
	tapRoutes = "activate — a tap, Return, or ButtonA",
	chord = "Context key",
	chordRoutes = "keyboard, gamepad — a tap does nothing here, on purpose",
	secondary = "Right-click",
	secondaryRoutes = "activate, secondary — a right-click is not an activate",
	hold = "Press and hold",
	holdRoutes = "activate, longPress — it opens before you lift your finger",
	disabled = "Nothing available",
	disabledRoutes = "activate — every item is unavailable, and it still opens",
	-- the menu itself (`f1`'s own list)
	accessory = "Accessory Adjustment",
	layering = "Layering",
	clothing = "Clothing Layering",
	makeup = "Makeup Layering",
	lips = "Lip Color",
	eyes = "Eye Color",
	skin = "Skin Color",
	report = "Report Avatar",
	reset = "Reset Avatar",
	-- the disabled menu's own verbs, so the two lists cannot be confused
	saveOutfit = "Save Outfit",
	shareOutfit = "Share Outfit",
	deleteOutfit = "Delete Outfit",
	-- the idiom control
	idiomTitle = "Idiom",
	idiomAuto = "Automatic",
	idiomPanel = "Panel",
	idiomSheet = "Sheet",
	idiomNote = "Automatic reads the live interaction classes. Panel and Sheet write the one fact that rule reads — a live touch class — so both idioms are reachable without a second device.",
	-- readouts
	openedTitle = "What opened, and what this app can tell about it",
	nothingYet = "nothing yet — open one of the cards above",
	closed = "closed",
	stateTitle = "What the framework reports",
	countsTitle = "Opens per card",
	diagTitle = "What the framework advises about this menu",
	noDiags = "nothing — the list is within the HIG's guidance",
	ranTitle = "Last verb run",
	ranNothing = "none — a disabled item runs nothing, which is the whole point of the last card",
	honestTitle = "The one thing this readout cannot say",
	honest = "Which trigger fired. `onOpen` takes no argument and `dump().triggers` is the set that was DECLARED, not the one that fired, so this fixture names the card and the live input classes instead. That is why the routes are split across cards rather than gathered on one.",
	depthNote = "Layering ▸ Makeup Layering is two levels deep. Right and Left enter and leave a level on a keyboard; Cancel or ButtonB closes one level and a tap outside closes all of them.",
}

local IDIOMS = { "auto", "panel", "sheet" }

return {
	title = "Menus and their five triggers",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("menu-scenario")
		local conditions = Facet.adaptive.conditions(core, ctx.env, { scope = scope })

		local lastOpen = scope:own(core:signal(COPY.nothingYet))
		local ran = scope:own(core:signal(COPY.ranNothing))
		local counts: { [string]: number } = {}
		local countsLine = scope:own(core:signal(""))
		local idiom = scope:own(core:signal("auto"))

		--[[ THE ONE FACT THE PRESENTATION RULE READS. `resolvePresentation` takes a
			`touchLive` boolean off the caller's interaction classes, so forcing an
			idiom is writing that fact rather than branching on a device — and it is a
			MEMO over the live classes, so "Automatic" is genuinely the environment's
			answer and not a third stored value. The classes are passed through
			unchanged in every other respect: a keyboard is still live under the sheet
			idiom, which is what keeps the sheet's rows reachable. ]]
		local liveClasses = ctx.env:get("interactionClasses")
		local classes = scope:own(core:memo(function(use)
			local live: any = use(liveClasses)
			local mode = use(idiom)
			if mode == "auto" then
				return live
			end
			local forced = if type(live) == "table" then table.clone(live) else {}
			forced.touch = mode == "sheet"
			forced.primary = if mode == "sheet" then "touch" else "pointer"
			return forced
		end))

		--[[ THE LIST, and it is one function rather than four copies — an `Item` is
			plain data with no state on it, so every card can hand the control its own
			fresh table off one definition. `f1`'s own verbs.

			THE ICON RULE IS PER GROUP AND ALL-OR-NOTHING (HIG: "provide icons for all
			menu items in a group, or none of them"), and a divider is what starts a
			new group — so the three items above the rule all carry one, the two below
			it both carry one, and the submenu levels carry none. Get it wrong and the
			control REFUSES rather than drawing a ragged column.

			FIVE ACTIONABLE ITEMS AT THE TOP LEVEL, WHICH IS THE CEILING AND IS
			DELIBERATE. The HIG's other advice — "if a submenu contains more than
			about five items, consider creating a new menu" — is diagnosed per LEVEL
			rather than per group, so a sixth verb here would put a second line in the
			readout below that this fixture never meant to demonstrate. The list is
			`f1`'s, one verb short.

			THE DESTRUCTIVE VERB IS LAST because anything else is diagnosed, and the
			nesting goes two levels deep on purpose: `api.diagnostics()` quotes the
			HIG at depth >= 2 and never refuses, which is SwiftUI's rule exactly. That
			advice is printed on the screen below rather than swallowed — it is the
			one diagnostic this list is meant to raise. ]]
		local function verbs(): { any }
			local function run(key: string)
				return function()
					ran:set(COPY[key])
				end
			end
			return {
				{ id = "accessory", label = COPY.accessory, icon = "edit", onSelect = run("accessory") },
				{
					id = "layering",
					label = COPY.layering,
					icon = "more",
					children = {
						{ id = "clothing", label = COPY.clothing, onSelect = run("clothing") },
						{
							id = "makeup",
							label = COPY.makeup,
							children = {
								{ id = "lips", label = COPY.lips, onSelect = run("lips") },
								{ id = "eyes", label = COPY.eyes, onSelect = run("eyes") },
							},
						},
					},
				},
				{ id = "skin", label = COPY.skin, icon = "edit", onSelect = run("skin") },
				{ divider = true },
				{ id = "report", label = COPY.report, icon = "flag", onSelect = run("report") },
				{
					id = "reset",
					label = COPY.reset,
					icon = "trash",
					role = "destructive",
					onSelect = run("reset"),
				},
			}
		end

		--[[ THE CARD THAT PROVES A REFUSAL. Every item is `enabled = false`, and the
			claim is that the trigger still works: the panel comes up, the verbs are
			readable, and none of them does anything. `enabled` is allowed to be a
			Readable, and it is a plain `false` here because the point is the state,
			not the reactivity. ]]
		local function unavailable(): { any }
			return {
				{ id = "save", label = COPY.saveOutfit, icon = "edit", enabled = false, onSelect = function() end },
				{ id = "share", label = COPY.shareOutfit, icon = "flag", enabled = false, onSelect = function() end },
				{ divider = true },
				{
					id = "delete",
					label = COPY.deleteOutfit,
					icon = "trash",
					role = "destructive",
					enabled = false,
					onSelect = function() end,
				},
			}
		end

		local cards: { any } = {}
		local function card(id: string, label: string, routes: string, triggers: { string }?, items: { any })
			local control = Facet.newMenu(Facet, core, {
				id = id,
				--[[ AN ORDINARY LABELLED BUTTON, and it carries NO `onActivate`. That
					absence is load-bearing rather than an omission: the presenter's
					activate dispatch tries a leaf's own `props.onActivate` BEFORE any
					contribution, so a trigger that declares one silently stops opening its
					own menu. The words matter more than a glyph here anyway — this card
					is a route, and its name is how a tester knows what to do to it.

					AND IT FILLS THE CARD, which is the half a device found (review
					2026-08-16, F1): *"I would expect that I could do the action in each
					thing on the entire row, not just the text."* A Button with no `width`
					HUGS its label, so this card read as a full-width row and took a press
					on 58 of its 312 pixels — the 44px floor's own defect family, turned
					ninety degrees. `newMenu` deliberately never touches its trigger's
					layout ("the contribution rides it; its layout is untouched"), so the
					row width is the AUTHOR's to declare and this is where it belongs. ]]
				trigger = UI.Button({
					id = `{id}Trigger`,
					label = label,
					width = { type = "fill", weight = 1 },
				}),
				items = items,
				triggers = triggers,
				sizeClass = conditions.sizeClass,
				interactionClasses = classes,
				onOpen = function()
					counts[id] = (counts[id] or 0) + 1
					--[[ THE HONEST READOUT. The card names the routes it accepts; the
						environment names the input classes that were live at the instant it
						opened. The framework names neither, which is the note at the foot of
						this screen. ]]
					local live: any = liveClasses:get()
					local names: { string } = {}
					for _, name in { "pointer", "touch", "keyboard", "gamepad" } do
						if type(live) == "table" and live[name] == true then
							table.insert(names, name)
						end
					end
					lastOpen:set(
						`{label} · routes: {routes} · live input: {if type(live) == "table"
							then tostring(live.primary)
							else "?"} ({table.concat(names, ", ")})`
					)
					local parts: { string } = {}
					for _, entry in cards do
						table.insert(parts, `{entry.label} {counts[entry.id] or 0}`)
					end
					countsLine:set(table.concat(parts, " · "))
				end,
			})
			scope:own(control)
			table.insert(cards, { id = id, label = label, routes = routes, control = control })
			return control
		end

		local avatar = card("Tap", COPY.tap, COPY.tapRoutes, { "activate" }, verbs())
		--[[ THE ONLY CARD WITHOUT `activate`, and the only one that may be: the
			control refuses that set unless BOTH chords are declared, so this is
			simultaneously the keyboard route, the gamepad route, and a demonstration
			of the three-axes rule that forced them to travel together. It is also the
			only card that owns the global chord context — two cards declaring
			`keyboard` would both open on one press, since equal-priority contexts do
			not sink each other. ]]
		card("Chord", COPY.chord, COPY.chordRoutes, { "keyboard", "gamepad" }, verbs())
		card("Secondary", COPY.secondary, COPY.secondaryRoutes, { "activate", "secondary" }, verbs())
		card("Hold", COPY.hold, COPY.holdRoutes, { "activate", "longPress" }, verbs())
		local blocked = card("Blocked", COPY.disabled, COPY.disabledRoutes, { "activate" }, unavailable())

		local parts: { string } = {}
		for _, entry in cards do
			table.insert(parts, `{entry.label} 0`)
		end
		countsLine:set(table.concat(parts, " · "))

		--[[ THE LIVE STATE LINE, and `surfaces` is the number it exists for: it
			climbs with the chain under `panel` and stays at 1 at any depth under
			`sheet`, where a submenu REPLACES the sheet rather than floating a second
			one over it. The two idioms are otherwise the same tree and the same
			verbs, so this count is the only thing on the screen that tells them apart.

			IT IS A TICK-REFRESHED SIGNAL RATHER THAN A MEMO OVER `isOpen`, and that
			was measured rather than assumed: a memo recomputes when its dependencies
			change, and `isOpen` is set to true BEFORE the first surface is presented
			— so the root level read `0 surface(s)` for as long as it stayed open, and
			a live idiom flip (which changes no signal this line reads, and really
			does rebuild the surfaces at the depth the player reached) never moved it
			at all. `put` is what makes the tick free: a frame in which the sentence
			did not change writes nothing and repaints nothing. ]]
		local stateLine = scope:own(core:signal(COPY.closed))
		local function put(signal: any, value: string)
			if signal:get() ~= value then
				signal:set(value)
			end
		end
		local function readState()
			for _, entry in cards do
				if entry.control.api.isOpen:get() then
					local chain = entry.control.api.openPath:get()
					local d = entry.control.dump()
					local where = if #chain == 0 then "root" else table.concat(chain, " ▸ ")
					put(
						stateLine,
						`{entry.label}: {d.presentation} · depth {#chain} ({where}) · {d.surfaces} surface(s)`
					)
					return
				end
			end
			put(stateLine, COPY.closed)
		end
		readState()
		if ctx.presenter ~= nil and ctx.presenter.onTick ~= nil then
			scope:own(ctx.presenter.onTick(readState))
		end

		local diagLine = scope:own(core:signal(COPY.noDiags))
		do
			local diags = avatar.api.diagnostics()
			if #diags > 0 then
				diagLine:set(table.concat(diags, "\n"))
			end
		end

		local idiomPicker = Facet.newPicker(Facet, core, {
			id = "Idiom",
			label = COPY.idiomTitle,
			presentation = "segmented",
			options = {
				{ value = "auto", label = COPY.idiomAuto },
				{ value = "panel", label = COPY.idiomPanel },
				{ value = "sheet", label = COPY.idiomSheet },
			},
			selected = idiom,
			sizeClass = conditions.sizeClass,
		})
		scope:own(idiomPicker)

		local function readout(id: string, title: string, body: any): any
			return UI.VStack({
				id = id,
				surface = "control",
				padding = "s",
				gap = "xs",
				width = { type = "fill", weight = 1 },
				children = {
					UI.Text({ id = "Title", text = title, textSize = "caption" }),
					UI.Text({ id = "Body", text = body, textSize = "caption", role = "secondary" }),
				},
			})
		end

		--[[ EACH TRIGGER IS A LABELLED CARD rather than a bare button, because the
			routes it accepts are the only thing that tells a tester what to DO to it
			— and they are read off the same `routes` string the readout prints, so
			the screen and the readout can never disagree about what a card takes. ]]
		local triggerCards: { any } = {}
		for _, entry in cards do
			table.insert(
				triggerCards,
				UI.VStack({
					id = `Card{entry.id}`,
					surface = "control",
					padding = "s",
					gap = "xs",
					width = { type = "fill", weight = 1 },
					children = {
						entry.control.blueprint,
						UI.Text({ id = "Routes", text = entry.routes, textSize = "caption", role = "secondary" }),
					},
				})
			)
		end

		local screen = UI.Screen({
			id = "MenuDemo",
			padding = "xs",
			gap = "xs",
			children = {
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "xs",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "heading" }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = "caption", role = "secondary" }),
						UI.VStack({
							id = "Cards",
							gap = "xs",
							align = "stretch",
							width = { type = "fill", weight = 1 },
							children = triggerCards,
						}),
						UI.VStack({
							id = "IdiomBox",
							surface = "control",
							padding = "s",
							gap = "xs",
							width = { type = "fill", weight = 1 },
							children = {
								idiomPicker.blueprint,
								UI.Text({
									id = "IdiomNote",
									text = COPY.idiomNote,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),
						readout("Opened", COPY.openedTitle, lastOpen),
						readout("State", COPY.stateTitle, stateLine),
						readout("Counts", COPY.countsTitle, countsLine),
						readout("Ran", COPY.ranTitle, ran),
						readout("Diag", COPY.diagTitle, diagLine),
						UI.Text({ id = "DepthNote", text = COPY.depthNote, textSize = "caption", role = "secondary" }),
						readout("Honest", COPY.honestTitle, COPY.honest),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			idiom = idiom,
			ran = ran,

			steps = {
				--[[ `api.open()` IS NOT A SIXTH TRIGGER and the readout says so: it is
					the caller opening its own menu, which every gesture route ends in. A
					headless step can reach this; only a person with the hardware can
					reach the four routes above it. ]]
				open = function(_built: any, payload: string?)
					local want = payload or "Tap"
					for _, entry in cards do
						if entry.id == want then
							local opened = entry.control.api.open()
							readState()
							return { opened = opened, dump = entry.control.dump(), state = stateLine:get() }
						end
					end
					return { opened = false }
				end,
				enter = function(_built: any, payload: string?)
					for _, entry in cards do
						if entry.control.api.isOpen:get() then
							local selected = entry.control.api.select(payload or "layering")
							readState()
							return { selected = selected, dump = entry.control.dump(), state = stateLine:get() }
						end
					end
					return { selected = false }
				end,
				back = function()
					for _, entry in cards do
						if entry.control.api.isOpen:get() then
							entry.control.api.closeLevel()
							readState()
							return { dump = entry.control.dump(), state = stateLine:get() }
						end
					end
					return {}
				end,
				close = function()
					for _, entry in cards do
						entry.control.api.close()
					end
					readState()
					return { state = stateLine:get() }
				end,
				idiom = function(_built: any, payload: string?)
					idiom:set(if payload ~= nil and table.find(IDIOMS, payload) ~= nil then payload else "auto")
					readState()
					return { idiom = idiom:get(), presentation = avatar.presentation(), state = stateLine:get() }
				end,
			},

			report = function()
				readState()
				local dumps: { any } = {}
				for _, entry in cards do
					table.insert(dumps, entry.control.dump())
				end
				return {
					cards = dumps,
					idiom = idiom:get(),
					presentation = avatar.presentation(),
					blockedPresentation = blocked.presentation(),
					diagnostics = avatar.api.diagnostics(),
					ran = ran:get(),
					lastOpen = lastOpen:get(),
					state = stateLine:get(),
				}
			end,

			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
