--!strict
-- Scenario 'adaptive_controls': the write-once proof (acceptance row A-AL4) and
-- the live fixture the five-view device matrix drives (rows D-1..D-6).
--
-- ONE semantic tree. There is no per-profile copy and no device-name branch: the
-- layout adapts from `LuauUI.adaptive.conditions` (space + viewing distance) and
-- from `UI.ViewThatFits` (the container's real measured space). Every Milestone B
-- control appears, so a single matrix sweep covers them all.

return {
	title = "Adaptive controls (write-once)",
	ledgerRows = {
		"A-AL4",
		"A-LV4",
		"B-BTN2",
		"B-VAL2",
		"B-VAL3",
		"B-DSP1",
		"B-DSP2",
		"D-1",
		"D-2",
		"D-3",
		"D-4",
		"D-5",
	},
	build = function(ctx: any)
		local LuauUI = ctx.LuauUI
		local UI = LuauUI.UI
		local core = ctx.core
		local scope = core:scope("adaptive-controls")
		local conditions = LuauUI.adaptive.conditions(core, ctx.env, { scope = scope }) -- RR-8: six memos die with the fixture

		-- owner-held state (it must outlive the controls, and it is what a live
		-- orientation change has to preserve)
		local volume = core:signal(6)
		local brightness = core:signal(40)
		local quality = core:signal("balanced")
		local advancedOpen = core:signal(false)
		local progress = core:signal(0.35)

		local stepper = LuauUI.newStepper(LuauUI, core, {
			id = "Volume",
			label = "Volume",
			value = volume,
			min = 0,
			max = 10,
			step = 1,
		})
		local slider = LuauUI.newSlider(LuauUI, core, {
			id = "Brightness",
			label = "Brightness",
			value = brightness,
			min = 0,
			max = 100,
			step = 5,
		})
		local picker = LuauUI.newPicker(LuauUI, core, {
			id = "Quality",
			label = "Quality",
			options = {
				{ value = "performance", label = "Performance" },
				{ value = "balanced", label = "Balanced" },
				{ value = "fidelity", label = "Fidelity" },
			},
			selected = quality,
			sizeClass = conditions.sizeClass,
		})
		local progressView = LuauUI.newProgressView(LuauUI, core, {
			id = "Download",
			label = "Download",
			value = progress,
			showValue = true,
		})
		local saveLabel = LuauUI.newLabel(LuauUI, core, { id = "SaveLabel", title = "Save changes" })
		local disclosure = LuauUI.newDisclosureGroup(LuauUI, core, {
			id = "Advanced",
			label = "Advanced",
			expanded = advancedOpen,
			content = function()
				return UI.VStack({
					id = "AdvancedBody",
					gap = 6,
					width = { type = "fill", weight = 1 },
					children = {
						UI.Toggle({ id = "Vsync", label = "Vertical sync", value = core:signal(true) }),
						UI.Toggle({ id = "Telemetry", label = "Share telemetry", value = core:signal(false) }),
					},
				})
			end,
		})

		-- the ACTION ROW is the ViewThatFits case: side by side when the container
		-- can hold it, stacked when it cannot. Measured, not guessed.
		local function actionButton(id: string, label: string, role: string?)
			return UI.Button({
				id = id,
				label = label,
				role = role,
				width = { type = "fill", weight = 1 },
				height = { type = "minMax", min = 44 },
			})
		end
		-- The action bar CAPS its width and centres (director review 2026-07-24):
		-- three fill buttons across a 1200px desktop made each one 400px wide, which
		-- reads as a mistake rather than a choice. `percent` with a max is the
		-- "full width, but no wider than this" shape. `align = "stretch"` equalises
		-- the button heights: the three labels wrap to different line counts, so
		-- without it the row is visibly ragged (68 / 89 / 68px on phone portrait).
		local actions = UI.ViewThatFits({
			id = "Actions",
			width = { type = "percent", fraction = 1, max = 620 },
			children = {
				UI.HStack({
					id = "ActionsRow",
					gap = 8,
					align = "stretch",
					width = { type = "fill", weight = 1 },
					children = {
						actionButton("Save", "Save changes"),
						actionButton("Reset", "Reset to defaults", "cancel"),
						actionButton("Delete", "Delete profile", "destructive"),
					},
				}),
				UI.VStack({
					id = "ActionsColumn",
					gap = 6,
					align = "stretch",
					width = { type = "fill", weight = 1 },
					children = {
						actionButton("Save", "Save changes"),
						actionButton("Reset", "Reset to defaults", "cancel"),
						actionButton("Delete", "Delete profile", "destructive"),
					},
				}),
			},
		})

		-- the SETTINGS/HUD split is an AdaptiveStack: side by side with room, stacked
		-- without. A flip is a re-solve, so nothing below remounts.
		local settingsColumn = UI.VStack({
			id = "Settings",
			gap = 10,
			width = { type = "fill", weight = 1 },
			children = {
				UI.Text({ id = "Heading", text = "Settings", textSize = 22 }),
				UI.Divider({}),
				stepper.blueprint,
				slider.blueprint,
				picker.blueprint,
				UI.Divider({}),
				disclosure.blueprint,
			},
		})
		-- A-LV4 shapes that had no fixture: an OVERLAY badge on a tile, a 16:9 media
		-- box via aspectRatio, and a toolbar row. None uses manual pixel positioning.
		-- The count is a REAL badge (`surface = "badge"`): under a flat theme it is
		-- the native circle-with-a-number, and a package with a badge recipe seals
		-- it and lifts the count centred — the count was unreadable when it was a
		-- corner-aligned bare Text.
		local function badgedTile(id: string, badge: string)
			return UI.overlay(
				UI.Box({
					id = id,
					surface = "control",
					width = { type = "fill", weight = 1 },
					height = { type = "fixed", px = 44 },
				}),
				UI.alignment(
					UI.padding(
						-- 28x28, NOT 24: the parchment seal is authored at 28x28 and
						-- its recipe reserves a 5px contentInset on every side, so the
						-- lifted count gets 28-10 = 18px of room. At 24 it got 14 —
						-- less than the ~14.4px line box a 12px glyph needs, which is
						-- the very clipping this fix round is closing. 28 also paints
						-- the seal at its native size, so nothing resamples.
						--
						-- textAlign is load-bearing too: the lift centres a badge's
						-- value only when a package actually skins it. On a FLAT theme
						-- the label draws its own text with the alignment it was
						-- given, and the default is start — so the unthemed "3" sat
						-- against the left edge of its circle, which is where the
						-- director found it.
						UI.Text({
							id = id .. "Badge",
							text = badge,
							textSize = 12,
							textAlign = "center",
							surface = "badge",
							width = { type = "fixed", px = 28 },
							height = { type = "fixed", px = 28 },
						}),
						2
					),
					"end",
					"start"
				)
			)
		end
		local toolbar = UI.HStack({
			id = "Toolbar",
			gap = 6,
			width = { type = "fill", weight = 1 },
			children = {
				UI.Button({ id = "TbBack", label = "◀", height = { type = "minMax", min = 44 } }),
				UI.Divider({ axis = "x" }),
				UI.Button({ id = "TbPlay", label = "Play", height = { type = "minMax", min = 44 } }),
				UI.Spacer({}),
				UI.Button({ id = "TbMore", label = "…", height = { type = "minMax", min = 44 } }),
			},
		})
		-- THE COMPACT-LABEL LADDER, on screen (compact-label stage, 2026-07-27).
		--
		-- Four buttons with the same full label. The first FILLS, so it says its
		-- whole label on a desktop and takes its compact form on a phone -- the
		-- ladder responding to the device, which is what this scenario is for. The
		-- other three are deliberately narrow so their rung is visible in every
		-- view at once: a shorter string, an icon, and -- as the control -- one
		-- that declares nothing and is therefore still where the ellipsis lives.
		--
		-- The fixed three are 52px rather than something roomier because the
		-- theme matrix rejected a wider row: four fixed boxes overflowed a compact
		-- phone by 2-7px under four packages. A `fill` first child absorbs the
		-- remainder instead, so the row cannot overrun any viewport.
		--
		-- AND 52 IS LESS THAN THE CHROME A BUTTON COSTS under half the shipped
		-- packages — 52 under Fantasy Ornate and Glossy Touch, 56 under Pixel Quest,
		-- before a single pixel of content (director report 2026-07-28, defect 3:
		-- the three buttons rendered BLANK under Glossy Touch). That is kept here
		-- ON PURPOSE now, because it is the live proof of the rule that report
		-- produced: a chrome inset is a REQUEST, and on a control too small to
		-- afford it the inset is given back so the content still draws, and the
		-- solver says so rather than the control going silently empty. Widening the
		-- row instead would have removed the only fixture that exercises it — and
		-- there is no width that works either way, because four skinned buttons and
		-- their gaps are 242px of pure border under Pixel Quest on a 288px phone.
		local compactWidth = { type = "fixed", px = 52 }
		--
		-- It rides THIS scenario because the five-view device matrix already drives
		-- it from phone to desktop under every package, which is the sweep that has
		-- caught every label-fitting defect so far. The `icon` button is also the
		-- device proof for the framework's own art: on a package that declines the
		-- set it must draw "/" and on every other one a pencil.
		local compactLadder = UI.HStack({
			id = "CompactRow",
			gap = 6,
			width = { type = "fill", weight = 1 },
			children = {
				UI.Button({
					id = "CmpRoomy",
					label = "Edit item",
					compactLabel = "Ed",
					width = { type = "fill", weight = 1 },
					height = { type = "minMax", min = 44 },
				}),
				UI.Button({
					id = "CmpText",
					label = "Edit item",
					compactLabel = "Ed",
					width = compactWidth,
					height = { type = "minMax", min = 44 },
				}),
				UI.Button({
					id = "CmpIcon",
					label = "Edit item",
					compactLabel = { icon = "edit" },
					width = compactWidth,
					height = { type = "minMax", min = 44 },
				}),
				UI.Button({
					id = "CmpNone",
					label = "Edit item",
					width = compactWidth,
					height = { type = "minMax", min = 44 },
				}),
			},
		})
		-- 16:9 media with NO hand arithmetic: the height follows the resolved width
		local media =
			UI.aspectRatio(UI.Box({ id = "Media", surface = "raised", width = { type = "fill", weight = 1 } }), 16 / 9)
		-- a DENSE HUD (A-AL4's second required surface): many small live readouts in
		-- a derived-column grid, not a settings form
		local hudTiles = {}
		for i = 1, 12 do
			table.insert(
				hudTiles,
				UI.background(
					UI.padding(
						UI.Text({ id = `Stat{i}`, text = `S{i}`, textSize = 12 }),
						{ top = 4, bottom = 4, left = 6, right = 6 }
					),
					UI.Box({ id = `StatPlate{i}`, surface = "control" })
				)
			)
		end

		local hudColumn = UI.VStack({
			id = "Hud",
			gap = 8,
			width = { type = "fill", weight = 1 },
			children = {
				UI.Text({ id = "HudHeading", text = "Status", textSize = 18 }),
				UI.Divider({}),
				toolbar,
				compactLadder,
				progressView.blueprint,
				saveLabel.blueprint,
				media,
				-- the dense readout field
				UI.Grid({
					id = "Stats",
					minColumnWidth = 48,
					gap = 4,
					width = { type = "fill", weight = 1 },
					children = hudTiles,
				}),
				-- a dense tile grid: fill cells occupy their derived columns (A-LV1)
				UI.Grid({
					id = "Tiles",
					minColumnWidth = 72,
					gap = 6,
					width = { type = "fill", weight = 1 },
					children = {
						badgedTile("t1", "3"),
						badgedTile("t2", "9"),
						badgedTile("t3", "1"),
						badgedTile("t4", "7"),
					},
				}),
			},
		})

		-- The body SCROLLS and the action bar stays PINNED — the standard settings
		-- shape, and the reason this fixture now fits on one screen.
		--
		-- It did not, before 2026-07-24. The Toolbar, 16:9 Media and 12-tile Stats
		-- surfaces were added to the Hud column after the five-view matrix had been
		-- driven, and nothing bounded the result: on compact-phone-portrait the body
		-- ran 115px past an 800px screen AT REST, painting the action row inside the
		-- Media box and dropping the stat grid and tile row off the bottom entirely.
		-- A stack does not compress to fit — it paints past its own box — so the
		-- content that exceeds a screen has to be given somewhere to go. The solver
		-- now REPORTS that condition (a-al4-preferred-text-sweep.json, PT-2); this
		-- is the fixture holding up its end.
		--
		-- The ScrollView takes `fill` so it absorbs whatever the pinned action bar
		-- leaves, at every viewport and every text scale, without arithmetic.
		local screen = UI.Screen({
			id = "AdaptiveScreen",
			padding = 16,
			gap = 12,
			-- centres the width-capped action bar; the scroll region is fill-width
			-- so it is unaffected
			align = "center",
			children = {
				UI.ScrollView({
					id = "BodyScroll",
					axis = "y",
					width = { type = "fill", weight = 1 },
					height = { type = "fill", weight = 1 },
					children = {
						UI.AdaptiveStack({
							id = "Body",
							axis = conditions.axis,
							gap = 16,
							width = { type = "fill", weight = 1 },
							children = { settingsColumn, hudColumn },
						}),
					},
				}),
				actions,
			},
		})

		return {
			screen = screen,
			dispose = function()
				stepper.dispose()
				slider.dispose()
				picker.dispose()
				progressView.dispose()
				saveLabel.dispose()
				disclosure.dispose()
				scope:dispose()
			end,
			steps = {
				-- state/action drivers (labeled: NOT hardware-input evidence)
				bumpVolume = function()
					volume:set(volume:get() + 1)
					return volume:get()
				end,
				openAdvanced = function()
					advancedOpen:set(true)
					return advancedOpen:get()
				end,
				closeAdvanced = function()
					advancedOpen:set(false)
					return advancedOpen:get()
				end,
				setProgress = function()
					progress:set(0.8)
					return progress:get()
				end,
				-- the STATE SNAPSHOT a live orientation change must preserve (D-2)
				snapshot = function()
					return {
						volume = volume:get(),
						brightness = brightness:get(),
						quality = quality:get(),
						advancedOpen = advancedOpen:get(),
						progress = progress:get(),
					}
				end,
			},
			report = function()
				return {
					sizeClass = conditions.sizeClass:get(),
					axis = conditions.axis:get(),
					isTenFoot = conditions.isTenFoot:get(),
					contentWidth = conditions.contentWidth:get(),
					pickerPresentation = picker.dump().presentation,
					stepper = stepper.dump(),
					slider = slider.dump(),
					picker = picker.dump(),
					progress = progressView.dump(),
					label = saveLabel.dump(),
					disclosure = disclosure.dump(),
					state = {
						volume = volume:get(),
						brightness = brightness:get(),
						quality = quality:get(),
						advancedOpen = advancedOpen:get(),
						progress = progress:get(),
					},
				}
			end,
		}
	end,
}
