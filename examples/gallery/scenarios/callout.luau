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
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local presenter = ctx.presenter
		local scope = core:scope("callout-scenario")

		--[[ THIS FIXTURE'S OWN SAVE FILE. Two plain signals standing in for
			whatever a real game would persist. The framework READS them and never
			writes them; the only thing it ever says back is `onRetire(reason)`, and
			what happens next is the two `:set` calls below — in this file, not in
			the framework. ]]
		local seen = scope:own(core:signal(false))
		local featureUsed = scope:own(core:signal(false))
		local saved = scope:own(core:signal(COPY.saveNothing))
		local reported = scope:own(core:signal("—"))
		local presses = scope:own(core:signal(0))
		local pressLine = scope:own(core:memo(function(use)
			return COPY.pressed .. tostring(use(presses))
		end))

		local function plate(title: string, sub: string): any
			return UI.VStack({
				id = "Body",
				gap = "xs",
				children = {
					UI.Text({ id = "Title", text = title, textSize = "body" }),
					UI.Text({ id = "Sub", text = sub, textSize = "caption", role = "secondary" }),
				},
			})
		end

		--[[ THE SESSION, AND WHY THE TWO COACH MARKS ARE NOT REBUILT (device review
			2026-08-16, F2). Director, round one: *"the tooltips also showed up the first
			time I pressed the buttons but then they stopped appearing."* Round two, on
			the fix: *"note that clicking start a fresh session removes the two buttons
			the tips attach to."*

			The first half was a framework defect (the tap-away catcher mounted OVER the
			screen it points at — fixed in `src/present/catchers.luau`). The second half
			is this construct working exactly as specified: `retired` is permanent BY
			CONTRACT, so once a plate has been put away or its feature used, `present()`
			refuses for the rest of the session. A demo of a once-per-player mechanism
			that can only be run once per launch is not a device pass.

			THE FIRST ANSWER WAS A KEYED `ForEach` OVER A SESSION NUMBER, and it is the
			one the director caught. Re-creating a callout re-creates the node it POINTS
			AT, and a coach mark's anchor is a PATH: every path under the row went from
			`[gen-1]/…` to `[gen-2]/…`, so anything already anchored to the old one was
			stranded. Measured with the ring on the left button — the focus-driven help
			plate re-presented against a path that did not have a rect yet and was placed
			at the viewport ORIGIN: a 284x55 raised plate at 0,0 sitting on an 80x46
			button at 12,12. From the couch that is the button disappearing.

			SO NOTHING ON THIS SCREEN IS REBUILT. The two anchors are permanent
			furniture, built once, at paths that never move; the session state is the two
			CONSTRUCTS, and `api.rearm()` is the framework's word for "the session the
			app persisted for is over" (the coach-mark datastore reset). The reset
			clears the save file and re-arms them in place. ]]
		local generation = scope:own(core:signal(1))

		--[[ THE f1 ANCHOR: a 44px `+` hard against the TOP-RIGHT corner, which is
			what makes the placement interesting — a centred plate under it would run a
			hundred pixels off the screen, so the solver shifts the body left and keeps
			the arrow over the button. It also carries `help`, so the same node
			demonstrates both mechanisms: hover it and the pulled plate appears; press
			"Show the coach mark" and the pushed one does. ]]
		local tip = scope:own(Facet.Controls.Callout(core, {
			id = "AvatarTip",
			anchor = UI.Button({
				id = "Plus",
				label = COPY.plus,
				help = COPY.helpPlus,
				anchor = "topRight",
				-- NOT a pinned 44px square. The 44 in the reference is a fact about the
				-- SCREENSHOT and it is asserted where it belongs, in
				-- `tests/callout.spec.luau`'s f1 case; pinning it here instead means a
				-- theme whose control chrome wants more room than that has to give its own
				-- border back, which the overflow sweep files as a finding on every
				-- viewport. The theme sizes its own controls.
				onActivate = function()
					presses:set(presses:get() + 1)
				end,
			}),
			content = plate(COPY.tipTitle, COPY.tipSub),
			dismissLabel = COPY.dismiss,
			seen = seen,
			featureUsed = featureUsed,
			priority = 1,
			onRetire = function(reason: string)
				-- THE WHOLE OF THE FRAMEWORK'S SIDE: one report, once.
				reported:set(reason)
				-- ...and the whole of the app's side, which is this line and only this
				-- line. Delete it and the tip comes back next session.
				seen:set(true)
				saved:set(`seen = true (because the framework reported "{reason}")`)
			end,
		}))

		-- a SECOND coach mark, so the queue is something a player can see rather than
		-- a claim in a document: ask for both and only one is ever up.
		local second = scope:own(Facet.Controls.Callout(core, {
			id = "ShareTip",
			anchor = UI.Button({
				id = "Share",
				label = COPY.share,
				help = COPY.helpShare,
				anchor = "topLeft",
			}),
			content = plate(COPY.secondTitle, COPY.secondSub),
			dismissLabel = COPY.dismiss,
			priority = 0,
			onRetire = function() end,
		}))

		local queueLine = scope:own(core:signal("—"))
		local stateLine = scope:own(core:signal("—"))
		-- ONE PAIR, FOR THE LIFE OF THE SCREEN, so this readout can close over them:
		-- the previous shape rebuilt the constructs on every reset and had to route
		-- every read through a live-pair table to avoid printing a disposed control's
		-- dump. Nothing is replaced now, so there is nothing to chase.
		local function readState()
			if presenter == nil then
				return
			end
			queueLine:set(presenter.callouts().text)
			stateLine:set(`{tip.dump().text}\n{second.dump().text}`)
		end
		readState()

		--[[ THE RESET, AND THE ORDER IS LOAD-BEARING. The save file is cleared BEFORE
			the constructs are re-armed, because `seen` and `featureUsed` are READ by
			`eligible()` and never written by the framework: re-arming first would leave
			two tips that answer "waiting" and refuse to present, which looks exactly
			like the defect this button exists to end. ]]
		local function resetSession()
			seen:set(false)
			featureUsed:set(false)
			saved:set(COPY.saveNothing)
			reported:set("—")
			generation:set(generation:get() + 1)
			tip.api.rearm()
			second.api.rearm()
		end

		local function pick(id: string, label: string, onPress: () -> ()): any
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

		local screen = UI.Screen({
			id = "CalloutDemo",
			padding = 12,
			gap = "s",
			children = {
				-- THE PERMANENT FURNITURE. Two anchors, built once, at paths that never
				-- move — which is what makes a coach mark's anchor (a PATH) survive a reset.
				UI.Anchor({
					id = "Bar",
					width = UI.fill(),
					height = UI.hug(),
					children = { second.blueprint, tip.blueprint },
				}),
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = "s",
					width = UI.fill(),
					height = UI.fill(),
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "control" }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = "caption", role = "secondary" }),
						UI.HStack({
							id = "Picks",
							gap = "tight",
							wrap = true,
							width = UI.fill(),
							children = {
								pick("Show", COPY.show, function()
									tip.api.present()
								end),
								pick("ShowSecond", COPY.showSecond, function()
									second.api.present()
								end),
								pick("Use", COPY.use, function()
									featureUsed:set(true)
								end),
								-- the button that makes this screen testable more than once
								pick("Reset", COPY.reset, resetSession),
							},
						}),
						UI.Text({ id = "Presses", text = pressLine, textSize = "caption" }),
						UI.Text({ id = "ResetNote", text = COPY.resetNote, textSize = "caption", role = "secondary" }),
						UI.VStack({
							id = "Queue",
							surface = "control",
							padding = "s",
							gap = "xs",
							width = UI.fill(),
							children = {
								UI.Text({ id = "QueueTitle", text = COPY.queueTitle, textSize = "caption" }),
								UI.Text({
									id = "QueueBody",
									text = queueLine,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),
						UI.VStack({
							id = "State",
							surface = "control",
							padding = "s",
							gap = "xs",
							width = UI.fill(),
							children = {
								UI.Text({ id = "StateTitle", text = COPY.stateTitle, textSize = "caption" }),
								UI.Text({
									id = "StateBody",
									text = stateLine,
									textSize = "caption",
									role = "secondary",
								}),
								UI.Text({ id = "Reported", text = reported, textSize = "caption", role = "secondary" }),
							},
						}),
						UI.VStack({
							id = "Save",
							surface = "control",
							padding = "s",
							gap = "xs",
							width = UI.fill(),
							children = {
								UI.Text({ id = "SaveTitle", text = COPY.saveTitle, textSize = "caption" }),
								UI.Text({ id = "SaveBody", text = saved, textSize = "caption", role = "secondary" }),
							},
						}),
						UI.VStack({
							id = "Help",
							surface = "control",
							padding = "s",
							gap = "xs",
							width = UI.fill(),
							children = {
								UI.Text({ id = "HelpTitle", text = COPY.helpTitle, textSize = "caption" }),
								UI.Text({
									id = "HelpBody",
									text = COPY.helpNote,
									textSize = "caption",
									role = "secondary",
								}),
							},
						}),
						UI.Text({ id = "Note", text = COPY.note, textSize = "caption", role = "secondary" }),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			presses = presses,
			seen = seen,

			-- The steps drive the SAME two constructs the buttons do, for the life of
			-- the screen: a reset re-arms them rather than replacing them, so there is no
			-- "which build is live" question left for a step to get wrong.
			steps = {
				show = function()
					tip.api.present()
					readState()
					return { state = tip.api.state() }
				end,
				showSecond = function()
					second.api.present()
					readState()
					return { showing = presenter and presenter.callouts().showing }
				end,
				use = function()
					featureUsed:set(true)
					readState()
					return { state = tip.api.state(), saved = saved:get() }
				end,
				reset = function()
					resetSession()
					readState()
					return { generation = generation:get() }
				end,
				reread = function()
					readState()
					return { queue = queueLine:get() }
				end,
			},

			report = function()
				return {
					tip = tip.dump(),
					second = second.dump(),
					queue = if presenter ~= nil then presenter.callouts() else nil,
					presses = presses:get(),
					seen = seen:get(),
					saved = saved:get(),
					generation = generation:get(),
				}
			end,

			-- the two constructs are the scope's (`scope:own`), so this is the whole
			-- teardown: one owner, one call, no bookkeeping list to keep in step
			dispose = function()
				scope:dispose()
			end,
		}
	end,
}
