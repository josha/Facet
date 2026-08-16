--!strict
--[[ Scenario 'callout' — THE TWO PLATES, AND WHO RAISED THEM
	(navigation-and-menus D3; reference `f1-avatar-editor.jpeg`).

	This screen exists because the two mechanisms it shows look almost identical
	in a still frame and are opposites in every other respect. Apple keeps them
	apart and so does LuauUI:

	  · `help` — the player PULLS it. Rest a pointer on a control, or land the
	    ring on it, and one sentence appears. On TOUCH nothing happens at all, by
	    specification: Apple binds no gesture to help on any platform, and the one
	    touch gesture that could carry it belongs to the full-value disclosure
	    plate. So the same words are also printed on this screen, which is exactly
	    the rule `text_audit.helpRoutes` enforces — help is never the only route.
	  · `newCallout` — the APP pushes it. It appears from eligibility rules with
	    an arrow tail, on every input class, and it retires permanently when the
	    feature is used or the player puts it away.

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
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
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

		--[[ THE f1 ANCHOR: a 44px `+` hard against the TOP-RIGHT corner, which is
			what makes the placement interesting — a centred plate under it would run
			a hundred pixels off the screen, so the solver shifts the body left and
			keeps the arrow over the button. It also carries `help`, so the same node
			demonstrates both mechanisms: hover it and the pulled plate appears; press
			"Show the coach mark" and the pushed one does. ]]
		local tip = LuauUI.newCallout(LuauUI, core, {
			id = "AvatarTip",
			anchor = UI.Button({
				id = "Plus",
				label = COPY.plus,
				help = COPY.helpPlus,
				anchor = "topRight",
				-- NOT a pinned 44px square. The 44 in the reference is a fact about
				-- the SCREENSHOT and it is asserted where it belongs, in
				-- `tests/callout.spec.luau`'s f1 case; pinning it here instead means
				-- a theme whose control chrome wants more room than that has to give
				-- its own border back, which the overflow sweep files as a finding on
				-- every viewport. The theme sizes its own controls.
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
				-- ...and the whole of the app's side, which is this line and only
				-- this line. Delete it and the tip comes back next session.
				seen:set(true)
				saved:set(`seen = true (because the framework reported "{reason}")`)
			end,
		})

		-- a SECOND coach mark, so the queue is something a player can see rather
		-- than a claim in a document: ask for both and only one is ever up.
		local second = LuauUI.newCallout(LuauUI, core, {
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
		})

		local queueLine = scope:own(core:signal("—"))
		local stateLine = scope:own(core:signal("—"))
		local function readState()
			if presenter == nil then
				return
			end
			local q = presenter.callouts()
			queueLine:set(q.text)
			stateLine:set(`{tip.dump().text}\n{second.dump().text}`)
		end
		readState()

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
			gap = 8,
			children = {
				UI.Anchor({
					id = "Bar",
					width = { type = "fill", weight = 1 },
					height = { type = "hug" },
					children = { second.blueprint, tip.blueprint },
				}),
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 8,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = 18 }),
						UI.Text({ id = "Intro", text = COPY.intro, textSize = 12, role = "secondary" }),
						UI.HStack({
							id = "Picks",
							gap = 6,
							wrap = true,
							width = { type = "fill", weight = 1 },
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
							},
						}),
						UI.Text({ id = "Presses", text = pressLine, textSize = 12 }),
						UI.VStack({
							id = "Queue",
							surface = "control",
							padding = 8,
							gap = 4,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "QueueTitle", text = COPY.queueTitle, textSize = 12 }),
								UI.Text({ id = "QueueBody", text = queueLine, textSize = 12, role = "secondary" }),
							},
						}),
						UI.VStack({
							id = "State",
							surface = "control",
							padding = 8,
							gap = 4,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "StateTitle", text = COPY.stateTitle, textSize = 12 }),
								UI.Text({ id = "StateBody", text = stateLine, textSize = 12, role = "secondary" }),
								UI.Text({ id = "Reported", text = reported, textSize = 12, role = "secondary" }),
							},
						}),
						UI.VStack({
							id = "Save",
							surface = "control",
							padding = 8,
							gap = 4,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "SaveTitle", text = COPY.saveTitle, textSize = 12 }),
								UI.Text({ id = "SaveBody", text = saved, textSize = 12, role = "secondary" }),
							},
						}),
						UI.VStack({
							id = "Help",
							surface = "control",
							padding = 8,
							gap = 4,
							width = { type = "fill", weight = 1 },
							children = {
								UI.Text({ id = "HelpTitle", text = COPY.helpTitle, textSize = 12 }),
								UI.Text({ id = "HelpBody", text = COPY.helpNote, textSize = 12, role = "secondary" }),
							},
						}),
						UI.Text({ id = "Note", text = COPY.note, textSize = 12, role = "secondary" }),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			presses = presses,
			seen = seen,

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
				}
			end,

			dispose = function()
				tip.dispose()
				second.dispose()
				scope:dispose()
			end,
		}
	end,
}
