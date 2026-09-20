--!strict
--[[ Scenario 'callout' — THE TWO PLATES, AND WHO RAISED THEM
	(navigation-and-menus D3; reference `f1-avatar-editor.jpeg`).

	This screen exists because the two mechanisms it shows look almost identical
	in a still frame and are opposites in every other respect. The conventions keep them
	apart and so does Facet:

	  · `help` — the player PULLS it. Rest a pointer on a control, or land the
	    ring on it, and one sentence appears. On TOUCH nothing happens at all, by
	    specification: no input class binds a gesture to help, and the one
	    touch gesture that could carry it belongs to the full-value disclosure
	    plate. So the same words are also printed on this screen, which is exactly
	    the rule `text_audit.helpRoutes` enforces — help is never the only route.
	  · `newCallout` — the APP pushes it. It appears from eligibility rules, on
	    every input class, and it retires permanently when the feature is used or
	    the player puts it away.

	Both plates carry D1's arrow tail (device review 2026-08-16, F4): the stem
	says WHICH CONTROL the words are about, and it never was what told the two
	mechanisms apart — who raises them, and whether they come back, is.

	THE f1 REPRODUCTION is the top-right `+`: the plate hangs BELOW it, its body
	is SHIFTED LEFT to stay on screen, and its arrow still points UP at the
	button. In the reference video that plate stays put while the player works the
	controls underneath it, so the counter below is not decoration — it is the
	non-blocking claim, on screen: the `+` still counts every press while the
	coach mark is pointing at it.

	AND THE PERSISTENCE BOUNDARY IS THE READOUT NOBODY ELSE CAN SHOW. The
	framework never writes player state; it reports. So this fixture keeps its own
	"save file" — two plain signals — and prints what the framework told it and
	what it chose to write. Those are two different columns on purpose.

	TWO HOSTS MOUNT THIS FILE and only one runs steps: the scenario runner drives
	`steps` by name, and the showcase demo picker mounts it with a minimal ctx and
	no step ever runs. Every button is an ordinary control with its own callback,
	so a player can drive the whole thing by hand.
]]

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy` — the
	contract `surface_overlap.luau` and `flow_wrap.luau` carry, because the
	gallery spec's localization case re-runs the fixture through a ~1.4x
	pseudo-localizing expansion and a check that cannot reach the strings cannot
	make that claim. Flat keys only. ]]
local COPY = {
	title = "Two plates, and who raised them",
	intro = "A tooltip is pulled by the player and shows nothing on touch. A coach mark is pushed by the app and shows on every input class.",
	plus = "+",
	share = "Share",
	tipTitle = "Post Avatars to Marketplace",
	tipSub = "Anyone can wear it",
	secondTitle = "Share your build",
	secondSub = "Friends can try it on",
	dismiss = "Got it",
	show = "Show the coach mark",
	showSecond = "Ask for a second one",
	use = "I used the feature",
	reset = "Start a fresh session",
	resetNote = "A retired coach mark never comes back — that is the contract, not a bug. The only thing that brings one back is a new session, so this button is what a new session IS: the save file is cleared and a fresh pair of coach marks is built. Without it this screen could be tested exactly once per launch.",
	pressed = "Presses on the + underneath: ",
	queueTitle = "The queue",
	stateTitle = "What the framework reports",
	saveTitle = "What THIS app chose to save",
	saveNothing = "nothing yet — the framework has written none of it",
	helpTitle = "Help is pulled, and it is never the only route",
	helpPlus = "Posts this avatar to the Marketplace",
	helpShare = "Shares this build with your friends",
	helpNote = "Hover the two buttons above with a pointer, or put the ring on them. On touch neither says anything — which is why both sentences are also printed here: Posts this avatar to the Marketplace. Shares this build with your friends.",
	note = "The coach mark never blocks: the + keeps counting presses underneath it, and one arrow press reaches the Got it row.",
}

return {
	title = "Coach marks and help",
	ledgerRows = {},
	copy = COPY,
	build = function(ctx: any)
		local UI, Compose = ctx.UI, ctx.Compose
		local presenter = ctx.presenter

		--[[ THIS FIXTURE'S OWN SAVE FILE. Two plain cells standing in for
			whatever a real game would persist. The framework READS them and never
			writes them; the only thing it ever says back is `onRetire(reason)`, and
			what happens next is the two `:set` calls below — in this file, not in
			the framework. ]]
		local seen = Compose.cell(false)
		local featureUsed = Compose.cell(false)
		local saved = Compose.cell(COPY.saveNothing)
		local reported = Compose.cell("—")
		local presses = Compose.cell(0)
		local pressLine = Compose.formula(function(use)
			return COPY.pressed .. tostring(use(presses))
		end)

		local function plate(title: string, sub: string): any
			return UI.VStack("Body")({
				gap = "xs",

				UI.Text("Title")({ text = title, textSize = "body" }),
				UI.Text("Sub")({ text = sub, textSize = "caption", role = "secondary" }),
			})
		end

		--[[ THE SESSION. `retired` is permanent BY CONTRACT: once a plate has been put
			away or its feature used, the construct refuses to present again. A demo of
			a once-per-player mechanism that can only be run once per launch is not a
			device pass, so this screen can start a new session.

			A NEW SESSION IS A NEW PAIR OF CONSTRUCTS UNDER THE SAME NAMES. A coach
			mark's anchor is a PATH, so the pair is rebuilt by a bare `Compose.keyed`,
			which adds no path segment: `/CalloutDemo/Bar/PlusSlot/Plus` is the same
			path in every session, and anything anchored to it stays anchored. ]]
		local generation = Compose.cell(1)

		-- What the screen knows about one coach mark: whether the app has asked for
		-- it, and what the construct has reported back through its callbacks.
		local function mark(id: string)
			return {
				id = id,
				requested = Compose.cell(false),
				showing = Compose.cell(false),
				retired = Compose.cell(false),
			}
		end
		local tip, second = mark("AvatarTip"), mark("ShareTip")
		local function stateOf(entry: any): string
			if entry.retired:peek() then
				return "retired"
			elseif entry.showing:peek() then
				return "showing"
			elseif entry.requested:peek() then
				return "queued"
			end
			return "waiting"
		end
		local function ask(entry: any)
			if not entry.retired:peek() then
				entry.requested:set(true)
			end
		end
		local function callbacks(entry: any, onRetire: (string) -> ())
			return {
				onShow = function()
					entry.showing:set(true)
				end,
				onHide = function()
					entry.showing:set(false)
					entry.requested:set(false)
				end,
				onRetire = function(reason: string)
					entry.retired:set(true)
					entry.requested:set(false)
					onRetire(reason)
				end,
			}
		end

		--[[ THE f1 ANCHOR: a `+` hard against the TOP-RIGHT corner, which is what
			makes the placement interesting — a centred plate under it would run a
			hundred pixels off the screen, so the solver shifts the body left and keeps
			the arrow over the button. It also carries `help`, so the same node
			demonstrates both mechanisms: hover it and the pulled plate appears; press
			"Show the coach mark" and the pushed one does. The theme sizes the button:
			the 44 in the reference is asserted in `tests/callout.spec.luau`. ]]
		local function avatarTip()
			local events = callbacks(tip, function(reason: string)
				-- THE WHOLE OF THE FRAMEWORK'S SIDE: one report, once.
				reported:set(reason)
				-- ...and the whole of the app's side, which is this line and only this
				-- line. Delete it and the tip comes back next session.
				seen:set(true)
				saved:set(`seen = true (because the framework reported "{reason}")`)
			end)
			return UI.HStack("PlusSlot")({
				anchor = "topRight",
				UI.Callout("AvatarTip")({
					anchor = UI.Button("Plus")({
						label = COPY.plus,
						help = COPY.helpPlus,
						onActivate = function()
							presses:set(presses:peek() + 1)
						end,
					}),
					content = function()
						return plate(COPY.tipTitle, COPY.tipSub)
					end,
					dismissLabel = COPY.dismiss,
					isPresented = tip.requested,
					seen = seen,
					featureUsed = featureUsed,
					priority = 1,
					onShow = events.onShow,
					onHide = events.onHide,
					onRetire = events.onRetire,
				}),
			})
		end

		-- a SECOND coach mark, so the queue is something a player can see rather than
		-- a claim in a document: ask for both and only one is ever up.
		local function shareTip()
			local events = callbacks(second, function() end)
			return UI.HStack("ShareSlot")({
				anchor = "topLeft",
				UI.Callout("ShareTip")({
					anchor = UI.Button("Share")({
						label = COPY.share,
						help = COPY.helpShare,
						onActivate = function() end,
					}),
					content = function()
						return plate(COPY.secondTitle, COPY.secondSub)
					end,
					dismissLabel = COPY.dismiss,
					isPresented = second.requested,
					priority = 0,
					onShow = events.onShow,
					onHide = events.onHide,
					onRetire = events.onRetire,
				}),
			})
		end

		local queueLine = Compose.cell("—")
		local stateLine = Compose.cell("—")
		local function readState()
			if presenter == nil then
				return
			end
			queueLine:set(presenter.callouts().text)
			stateLine:set(`{tip.id}: {stateOf(tip)}\n{second.id}: {stateOf(second)}`)
		end
		readState()

		--[[ THE RESET, AND THE ORDER IS LOAD-BEARING. The save file is cleared BEFORE
			the new pair is built, because a construct reads `seen` and `featureUsed`
			as it is built: built first, the pair would open already retired. ]]
		local function resetSession()
			seen:set(false)
			featureUsed:set(false)
			saved:set(COPY.saveNothing)
			reported:set("—")
			for _, entry in { tip, second } do
				entry.requested:set(false)
				entry.showing:set(false)
				entry.retired:set(false)
			end
			generation:set(generation:peek() + 1)
		end

		local function pick(id: string, label: string, onPress: () -> ()): any
			return UI.Button(id)({
				label = label,
				surface = "chip",
				onActivate = function()
					onPress()
					readState()
				end,
			})
		end

		local function Example()
			return UI.Screen("CalloutDemo")({
				padding = 12,
				gap = "s",

				-- THE TWO ANCHORS, at paths that never move — which is what lets a
				-- coach mark's anchor (a PATH) survive a reset.
				UI.Anchor("Bar")({
					width = UI.fill(),
					height = UI.hug(),
					Compose.keyed({
						from = function(use)
							local session = use(generation)
							return {
								{ key = `share-{session}`, build = shareTip },
								{ key = `plus-{session}`, build = avatarTip },
							}
						end,
						key = function(entry)
							return entry.key
						end,
						render = function(entry)
							return entry:peek().build()
						end,
					}),
				}),
				UI.ScrollView("Page")({
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),

					UI.Text("Title")({ text = COPY.title, textSize = "control" }),
					UI.Text("Intro")({ text = COPY.intro, textSize = "caption", role = "secondary" }),
					UI.HStack("Picks")({
						gap = "tight",
						wrap = true,
						width = UI.fill(),

						pick("Show", COPY.show, function()
							ask(tip)
						end),
						pick("ShowSecond", COPY.showSecond, function()
							ask(second)
						end),
						pick("Use", COPY.use, function()
							featureUsed:set(true)
						end),
						-- the button that makes this screen testable more than once
						pick("Reset", COPY.reset, resetSession),
					}),
					UI.Text("Presses")({ text = pressLine, textSize = "caption" }),
					UI.Text("ResetNote")({ text = COPY.resetNote, textSize = "caption", role = "secondary" }),
					UI.VStack("Queue")({
						surface = "control",
						padding = "s",
						gap = "xs",
						width = UI.fill(),

						UI.Text("QueueTitle")({ text = COPY.queueTitle, textSize = "caption" }),
						UI.Text("QueueBody")({
							text = queueLine,
							textSize = "caption",
							role = "secondary",
						}),
					}),
					UI.VStack("State")({
						surface = "control",
						padding = "s",
						gap = "xs",
						width = UI.fill(),

						UI.Text("StateTitle")({ text = COPY.stateTitle, textSize = "caption" }),
						UI.Text("StateBody")({
							text = stateLine,
							textSize = "caption",
							role = "secondary",
						}),
						UI.Text("Reported")({ text = reported, textSize = "caption", role = "secondary" }),
					}),
					UI.VStack("Save")({
						surface = "control",
						padding = "s",
						gap = "xs",
						width = UI.fill(),

						UI.Text("SaveTitle")({ text = COPY.saveTitle, textSize = "caption" }),
						UI.Text("SaveBody")({ text = saved, textSize = "caption", role = "secondary" }),
					}),
					UI.VStack("Help")({
						surface = "control",
						padding = "s",
						gap = "xs",
						width = UI.fill(),

						UI.Text("HelpTitle")({ text = COPY.helpTitle, textSize = "caption" }),
						UI.Text("HelpBody")({
							text = COPY.helpNote,
							textSize = "caption",
							role = "secondary",
						}),
					}),
					UI.Text("Note")({ text = COPY.note, textSize = "caption", role = "secondary" }),
				}),
			})
		end

		return {
			screen = Example,
			present = {},
			presses = presses,
			seen = seen,

			-- The steps write the SAME cells the buttons do.
			steps = {
				show = function()
					ask(tip)
					readState()
					return { state = stateOf(tip) }
				end,
				showSecond = function()
					ask(second)
					readState()
					return { showing = presenter and presenter.callouts().showing }
				end,
				use = function()
					featureUsed:set(true)
					readState()
					return { state = stateOf(tip), saved = saved:peek() }
				end,
				reset = function()
					resetSession()
					readState()
					return { generation = generation:peek() }
				end,
				reread = function()
					readState()
					return { queue = queueLine:peek() }
				end,
			},

			report = function()
				return {
					tip = { id = tip.id, state = stateOf(tip) },
					second = { id = second.id, state = stateOf(second) },
					queue = if presenter ~= nil then presenter.callouts() else nil,
					presses = presses:peek(),
					seen = seen:peek(),
					saved = saved:peek(),
					generation = generation:peek(),
				}
			end,

			dispose = function() end,
		}
	end,
}
