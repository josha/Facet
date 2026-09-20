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

	The five cards demonstrate activation, focused context commands, secondary
	click, long press and unavailable verbs. The secondary card omits activate;
	keyboard and gamepad context commands remain available when it has focus.

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
	interaction class — and then `newMenu`'s own automatic resolution (director
	item 14) forces `sheet` whenever the space class is COMPACT,
	regardless of which pointer is live: a floating per-level panel does not fit
	a phone width no matter what moved it. So the Idiom picker below writes the
	ONE input `resolvePresentation` reads, and both idioms are reachable in one
	session on one machine ONLY at a regular width or wider — narrow this window
	past compact and Panel stops being reachable, on purpose:

	  · panel — each submenu level is its own surface anchored to its parent ROW;
	  · sheet — the touch idiom, and also the compact-width idiom, where a
	    submenu REPLACES the sheet's contents and grows a Back row.

	AND ONE CARD EXISTS FOR A REFUSAL: a menu whose every item is disabled still
	OPENS. The guidance: if all of a menu's items are unavailable, the menu itself needs
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
	secondaryRoutes = "Right click here; focus here for Menu / Shift+F10 / Y",
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
	idiomNote = "Automatic reads the live interaction classes AND the space class. Panel and Sheet write the one fact the interaction rule reads — a live touch class — so both idioms are reachable without a second device at a regular width or wider. At a COMPACT width the framework always resolves Sheet, on purpose (director item 14): forcing Panel there still shows Sheet, because a floating per-level panel does not fit a phone regardless of which pointer moved it. Widen the window past a compact width to see Panel's floating, side-by-side submenus.",
	-- readouts
	openedTitle = "What opened, and what this app can tell about it",
	nothingYet = "nothing yet — open one of the cards above",
	closed = "closed",
	open = "open",
	stateTitle = "What the framework reports",
	countsTitle = "Opens per card",
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
		local UI, Compose = ctx.UI, ctx.Compose

		local lastOpen = Compose.cell(COPY.nothingYet)
		local ran = Compose.cell(COPY.ranNothing)
		local counts: { [string]: number } = {}
		local countsLine = Compose.cell("")
		local idiom = Compose.cell("auto")

		--[[ THE ONE FACT THE PRESENTATION RULE READS. `resolvePresentation` takes a
			`touchLive` boolean off the caller's interaction classes, so forcing an
			idiom is writing that fact rather than branching on a device — and it is a
			MEMO over the live classes, so "Automatic" is genuinely the environment's
			answer and not a third stored value. The classes are passed through
			unchanged in every other respect: a keyboard is still live under the sheet
			idiom, which is what keeps the sheet's rows reachable. ]]
		local liveClasses = ctx.env:get("interactionClasses")
		local classes = Compose.formula(function(use)
			local live: any = use(liveClasses)
			local mode = use(idiom)
			if mode == "auto" then
				return live
			end
			local forced = if type(live) == "table" then table.clone(live) else {}
			forced.touch = mode == "sheet"
			forced.primary = if mode == "sheet" then "touch" else "pointer"
			return forced
		end)

		--[[ THE LIST, and it is one function rather than four copies — an `Item` is
			plain data with no state on it, so every card can hand the control its own
			fresh table off one definition. `f1`'s own verbs.

			THE ICON RULE IS PER GROUP AND ALL-OR-NOTHING (provide icons for all
			menu items in a group, or none of them), and a divider is what starts a
			new group — so the three items above the rule all carry one, the two below
			it both carry one, and the submenu levels carry none. Get it wrong and the
			control REFUSES rather than drawing a ragged column.

			FIVE ACTIONABLE ITEMS AT THE TOP LEVEL, WHICH IS THE CEILING AND IS
			DELIBERATE. The other standing advice — if a submenu contains more than
			about five items, consider creating a new menu" — is diagnosed per LEVEL
			rather than per group, so a sixth verb here would put a second line in the
			readout below that this fixture never meant to demonstrate. The list is
			`f1`'s, one verb short.

			THE DESTRUCTIVE VERB IS LAST because anything else is diagnosed, and the
			nesting goes two levels deep on purpose: the control advises against
			depth >= 2 and never refuses it. ]]
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

		--[[ THE FIVE CARDS, as data. Each names the routes it accepts, and the
			readout prints the same string, so the screen and the readout can never
			disagree about what a card takes. ]]
		local CARDS = {
			{ id = "Tap", label = COPY.tap, routes = COPY.tapRoutes, triggers = { "activate" }, items = verbs },
			{
				id = "Chord",
				label = COPY.chord,
				routes = COPY.chordRoutes,
				triggers = { "keyboard", "gamepad" },
				items = verbs,
			},
			{
				id = "Secondary",
				label = COPY.secondary,
				routes = COPY.secondaryRoutes,
				triggers = { "secondary", "keyboard", "gamepad" },
				items = verbs,
			},
			{
				id = "Hold",
				label = COPY.hold,
				routes = COPY.holdRoutes,
				triggers = { "activate", "longPress" },
				items = verbs,
			},
			{
				id = "Blocked",
				label = COPY.disabled,
				routes = COPY.disabledRoutes,
				triggers = { "activate" },
				items = unavailable,
			},
		}

		local function countsText(): string
			local parts: { string } = {}
			for _, entry in CARDS do
				table.insert(parts, `{entry.label} {counts[entry.id] or 0}`)
			end
			return table.concat(parts, " · ")
		end
		countsLine:set(countsText())

		-- Which card is open, from the two callbacks the control gives its caller.
		local stateLine = Compose.cell(COPY.closed)

		local function card(entry: any, conditions: any): any
			--[[ THE TRIGGER IS THE MENU'S OWN LABELLED BUTTON, and it fills the card
				(review 2026-08-16, F1: a Button with no `width` HUGS its label, so the
				card read as a full-width row and took a press on 58 of its 312 pixels).
				The control never touches its trigger's layout, so the row width is the
				AUTHOR's to declare, and this is where it belongs. ]]
			local menu = UI.frame(
				UI.Menu(entry.id)({
					label = entry.label,
					items = entry.items(),
					triggers = entry.triggers,
					sizeClass = conditions.sizeClass,
					interactionClasses = classes,
					onOpen = function()
						counts[entry.id] = (counts[entry.id] or 0) + 1
						--[[ THE HONEST READOUT. The card names the routes it accepts; the
							environment names the input classes that were live at the instant
							it opened. The framework names neither, which is the note at the
							foot of this screen. ]]
						local live: any = liveClasses:peek()
						local names: { string } = {}
						for _, name in { "pointer", "touch", "keyboard", "gamepad" } do
							if type(live) == "table" and live[name] == true then
								table.insert(names, name)
							end
						end
						lastOpen:set(
							`{entry.label} · routes: {entry.routes} · live input: {if type(live) == "table"
								then tostring(live.primary)
								else "?"} ({table.concat(names, ", ")})`
						)
						countsLine:set(countsText())
						stateLine:set(`{entry.label}: {COPY.open}`)
					end,
					onClose = function()
						stateLine:set(COPY.closed)
					end,
				}),
				{ maxWidth = "infinity" }
			)
			return UI.VStack(`Card{entry.id}`)({
				surface = "control",
				padding = "s",
				gap = "xs",
				width = UI.fill(),

				menu,
				UI.Text("Routes")({ text = entry.routes, textSize = "caption", role = "secondary" }),
			})
		end

		local function readout(id: string, title: string, body: any): any
			return UI.VStack(id)({
				surface = "control",
				padding = "s",
				gap = "xs",
				width = UI.fill(),

				UI.Text("Title")({ text = title, textSize = "caption" }),
				UI.Text("Body")({ text = body, textSize = "caption", role = "secondary" }),
			})
		end

		local function screen()
			local conditions = Facet.adaptive.conditions(ctx.env)
			local cardRow: { any } = { gap = "xs", align = "stretch", width = UI.fill() }
			for _, entry in CARDS do
				table.insert(cardRow, card(entry, conditions))
			end
			return UI.Screen("MenuDemo")({
				padding = "xs",
				gap = "xs",

				UI.ScrollView("Page")({
					axis = "y",
					gap = "xs",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = COPY.title, textSize = "heading" }),
					UI.Text("Intro")({ text = COPY.intro, textSize = "caption", role = "secondary" }),
					UI.VStack("Cards")(cardRow),
					UI.VStack("IdiomBox")({
						surface = "control",
						padding = "s",
						gap = "xs",
						width = UI.fill(),

						UI.Picker("Idiom")({
							label = COPY.idiomTitle,
							style = "segmented",
							options = {
								{ value = "auto", label = COPY.idiomAuto },
								{ value = "panel", label = COPY.idiomPanel },
								{ value = "sheet", label = COPY.idiomSheet },
							},
							selected = idiom,
							sizeClass = conditions.sizeClass,
						}),
						UI.Text("IdiomNote")({
							text = COPY.idiomNote,
							textSize = "caption",
							role = "secondary",
						}),
					}),
					readout("Opened", COPY.openedTitle, lastOpen),
					readout("State", COPY.stateTitle, stateLine),
					readout("Counts", COPY.countsTitle, countsLine),
					readout("Ran", COPY.ranTitle, ran),
					UI.Text("DepthNote")({ text = COPY.depthNote, textSize = "caption", role = "secondary" }),
					readout("Honest", COPY.honestTitle, COPY.honest),
				}),
			})
		end

		return {
			screen = screen,
			present = {},
			idiom = idiom,
			ran = ran,

			steps = {
				idiom = function(_built: any, payload: string?)
					idiom:set(if payload ~= nil and table.find(IDIOMS, payload) ~= nil then payload else "auto")
					return { idiom = idiom:peek() }
				end,
			},

			report = function()
				return {
					idiom = idiom:peek(),
					ran = ran:peek(),
					lastOpen = lastOpen:peek(),
					state = stateLine:peek(),
					counts = table.clone(counts),
				}
			end,
		}
	end,
}
