--!strict
--[[ Scenario 'preferred_transparency' — THE PLAYER'S BACKGROUND TRANSPARENCY
	SETTING, ANSWERED BY FACET'S OWN PAINTING (ADR-0035, owed row O-26).

	WHY THIS FIXTURE EXISTS AT ALL. `GuiService.PreferredTransparency` reached the
	environment four stages ago and nothing read it, so a player who turned the
	setting down saw no change anywhere in Facet. The row that recorded that was
	left open deliberately, because a DEMO would have had to honour the preference
	by hand — consumer code advertising a capability the framework did not have.
	So this fixture contains no honouring at all. It moves the PREFERENCE; every
	pixel that answers is painted by the framework.

	THE SLIDER IS NOT THE FEATURE, and the caption on screen says so. On a real
	device the number comes from Settings → Accessibility → Background
	Transparency, and `roblox_env` pushes it into `preferredTransparency` on the
	property's own change signal. Measured 2026-08-15 in Studio: a game script
	CANNOT write it (`GuiService.PreferredTransparency` is read-only, and
	`UserGameSettings.PreferredTransparency` refuses a non-RobloxScript thread), so
	a fixture that wants to show the response has to drive the environment fact the
	adapter would have written. That is the same seam `preferred_text` drives, and
	it is the honest one: everything downstream of the fact is production code.

	THREE THINGS ON ONE SCREEN, because the interesting half of this feature is
	what does NOT move:

	  · THE BACKDROP swatch (`surface = "scrim"`) — the framework's one see-through
	    background, and the one thing here that answers the setting. At 0 it is a
	    solid panel; at 1 it is the theme's own dim.
	  · THE PANEL swatch (`surface = "raised"`) — already opaque, so there is
	    nothing for a transparency preference to do. It is here to be identical in
	    every state, which is what makes the backdrop's change legible.
	  · THE AUTHORED FADE (`UI.ZStack{ opacity = 0.5 }`) — an author's explicit
	    number, and the preference never touches it. If it did, an author's 0.5
	    would silently become something else and every running `withAnimation`
	    fade would be retargeted mid-flight. That refusal is invisible unless
	    something on screen is holding still while its neighbour moves.

	...AND THEN THE REAL ONE: the dialog. Open it and the backdrop behind it is the
	presenter's own synthesized scrim (`present/catchers.luau`), which no
	declaration in this file reaches — it is the framework painting its own
	furniture at the player's setting.

	TWO HOSTS, one contract (the pair `lifecycle_hidden.luau` documents): the
	scenario runner drives `steps` by name, and the showcase demo picker mounts it
	with a minimal ctx and no step ever runs. Every control here is an ordinary
	button with its own callback, so a player drives all of it by hand.
]]

--[[ EVERY PLAYER-VISIBLE STRING, in one table and EXPORTED as `copy`, so
	`tests/examples_gallery.spec.luau`'s localization case can expand all of it
	~1.4x. All `policy = "none"` copy: it must fit and wrap, never clip. ]]
local COPY = {
	title = "Background Transparency",
	caption = "Roblox publishes the player's Background Transparency setting. Facet reads it and paints its own backdrops with it — nothing here honours it by hand.",
	setting = "Your setting",
	realHint = "On a device this comes from Settings → Accessibility. A game script cannot write it, so this drives the same environment fact the adapter publishes.",
	backdrop = "Backdrop",
	backdropHint = "answers the setting",
	panel = "Panel",
	panelHint = "already opaque",
	fade = "Authored fade",
	fadeHint = "the author's 0.5, untouched",
	open = "Open a dialog",
	close = "Close",
	dialogTitle = "The backdrop behind this",
	dialogBody = "This dim is the presenter's own scrim. Nothing in the fixture declared it.",
	note = "A see-through background is the only thing that moves. A border, a shadow, a disabled dim and an authored opacity all stay where they were — each of them means something a transparency preference is not about.",
	readout = "Setting",
}

-- the five stops, in the order a player reads them: the default first, fully
-- opaque last. The labels carry the number so a screenshot is self-describing.
local STOPS = {
	{ id = "Full", label = "1.0 default", value = 1 },
	{ id = "Three", label = "0.75", value = 0.75 },
	{ id = "Half", label = "0.5", value = 0.5 },
	{ id = "Quarter", label = "0.25", value = 0.25 },
	{ id = "Opaque", label = "0 opaque", value = 0 },
}

return {
	title = "Background Transparency preference (ADR-0035)",
	ledgerRows = {},
	copy = COPY,
	stops = STOPS,
	build = function(ctx: any)
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local env = ctx.env
		local pres = ctx.presenter
		local scope = core:scope("preferred-transparency")

		-- the fixture's own mirror of the fact, so the readout and the chip
		-- selection have something to bind to. The FACT is the authority: this is
		-- written in the same call that writes it, never read back from paint.
		local setting = scope:own(core:signal(1))

		local function apply(value: number)
			setting:set(value)
			if env ~= nil then
				env:set("preferredTransparency", value)
			end
		end

		local readout = scope:own(core:memo(function(use)
			return `{COPY.readout}: {string.format("%.2f", use(setting))}`
		end))

		local dialog: any = nil
		local function closeDialog()
			if dialog ~= nil then
				pres.dismiss(dialog)
				dialog = nil
				pres.refresh()
			end
		end
		local function openDialog()
			if dialog ~= nil then
				return
			end
			dialog = pres.presentModal(UI.Screen({
				id = "TransparencyDialog",
				padding = 20,
				gap = 10,
				width = { type = "fixed", px = 300 },
				children = {
					UI.Text({ id = "DTitle", text = COPY.dialogTitle, textSize = "heading" }),
					UI.Text({ id = "DBody", text = COPY.dialogBody, textSize = "caption", role = "secondary" }),
					UI.Button({ id = "DClose", label = COPY.close, onActivate = closeDialog }),
				},
			}))
			pres.refresh()
		end

		-- ONE swatch shape for all three, so the only difference a player can see
		-- between them is the declaration each carries
		local function swatch(id: string, label: string, hint: string, body: any): any
			return UI.VStack({
				id = id,
				gap = 4,
				width = { type = "fixed", px = 132 },
				children = {
					body,
					UI.Text({ id = "Label", text = label, textSize = "label" }),
					UI.Text({ id = "Hint", text = hint, textSize = "caption", role = "secondary" }),
				},
			})
		end

		local stopChips: { any } = {}
		for _, stop in STOPS do
			table.insert(
				stopChips,
				UI.Button({
					id = stop.id,
					label = stop.label,
					onActivate = function()
						apply(stop.value)
					end,
				})
			)
		end

		local screen = UI.Screen({
			id = "PreferredTransparency",
			padding = 16,
			children = {
				UI.ScrollView({
					id = "Page",
					axis = "y",
					gap = 10,
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.Text({ id = "Title", text = COPY.title, textSize = "title" }),
						UI.Text({ id = "Caption", text = COPY.caption, textSize = "caption", role = "secondary" }),
						UI.Text({ id = "SettingLabel", text = COPY.setting, textSize = "label" }),
						UI.HStack({ id = "Stops", gap = 6, wrap = true, children = stopChips }),
						UI.Text({ id = "Readout", text = readout, textSize = "label" }),
						UI.Text({ id = "RealHint", text = COPY.realHint, textSize = "caption", role = "secondary" }),
						UI.HStack({
							id = "Swatches",
							gap = 10,
							wrap = true,
							children = {
								swatch(
									"BackdropSwatch",
									COPY.backdrop,
									COPY.backdropHint,
									-- the ONE declaration on this page that the
									-- preference reaches: a backdrop says it means
									-- to be seen through
									UI.Box({
										id = "Fill",
										surface = "scrim",
										width = { type = "fill", weight = 1 },
										height = { type = "fixed", px = 72 },
									})
								),
								swatch(
									"PanelSwatch",
									COPY.panel,
									COPY.panelHint,
									UI.Box({
										id = "Fill",
										surface = "raised",
										width = { type = "fill", weight = 1 },
										height = { type = "fixed", px = 72 },
									})
								),
								swatch(
									"FadeSwatch",
									COPY.fade,
									COPY.fadeHint,
									UI.ZStack({
										id = "Fill",
										opacity = 0.5,
										width = { type = "fill", weight = 1 },
										height = { type = "fixed", px = 72 },
										children = {
											UI.Box({
												id = "Plate",
												surface = "raised",
												width = { type = "fill", weight = 1 },
												height = { type = "fill", weight = 1 },
											}),
										},
									})
								),
							},
						}),
						UI.Button({ id = "Open", label = COPY.open, onActivate = openDialog }),
						UI.Text({ id = "Note", text = COPY.note, textSize = "caption", role = "secondary" }),
					},
				}),
			},
		})

		return {
			screen = screen,
			present = {},
			steps = {
				setFull = function()
					apply(1)
					return { setting = setting:get() }
				end,
				setHalf = function()
					apply(0.5)
					return { setting = setting:get() }
				end,
				setOpaque = function()
					apply(0)
					return { setting = setting:get() }
				end,
				openDialog = function()
					openDialog()
					return { open = dialog ~= nil, depth = pres.depth() }
				end,
				closeDialog = function()
					closeDialog()
					return { open = dialog ~= nil, depth = pres.depth() }
				end,
			},
			report = function()
				local effective: any = nil
				if env ~= nil then
					local ok, value = pcall(function()
						return env:get("effectiveTransparency"):get()
					end)
					effective = if ok then value else nil
				end
				return {
					setting = setting:get(),
					-- the DERIVED value the framework actually paints with, read
					-- from the environment rather than recomputed here
					effectiveTransparency = effective,
					dialogOpen = dialog ~= nil,
					scrimPath = pres.topScrimPath(),
				}
			end,
			dispose = function()
				closeDialog()
				scope:dispose()
			end,
		}
	end,
}
