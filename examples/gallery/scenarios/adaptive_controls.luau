--!strict
-- Scenario 'adaptive_controls': the write-once proof (acceptance row A-AL4) and
-- the live fixture the five-view device matrix drives (rows D-1..D-6).
--
-- ONE semantic tree. There is no per-profile copy and no device-name branch: the
-- layout adapts from `Facet.adaptive.conditions` (space + viewing distance) and
-- from `UI.ViewThatFits` (the container's real measured space). Every Milestone B
-- control appears, so a single matrix sweep covers them all.
--
-- ...AND, SINCE parity round 2, THE LAYOUT VOCABULARY THAT ROUND ADDED
-- (`docs/plans/parity-round2.md` §2.1/2.2/2.4/2.5/2.6, §3.3). The plan
-- names this fixture as the natural home for the ADAPTIVE members of that
-- vocabulary, and the reason is the same one that put the compact-label ladder
-- here: this is the surface the five-view device matrix and the always-on
-- overflow sweep already drive from a 320px phone to a ten-foot console, so a
-- prop whose whole subject is "what happens when the space changes" is under
-- observation at every width for free. The block lives at the bottom of the HUD
-- column and is headed `VocabHeading` on screen. What it carries:
--
--   * `distribute`               (§2.6) — the legend row spreads its three
--                                 markers edge to edge instead of packing left
--   * `layoutPriority` +         (§2.4) — the three bars below it overflow a
--     `shrinkWeight`                     phone and give way in priority order:
--                                        Optional first, then Useful, and
--                                        Essential never (it declares no weight)
--   * `lineAlign`                (§2.1) — Essential is a short bar sitting on
--                                        the BOTTOM of a line its siblings set
--   * `containerRelativeFrame`   (§2.5) — the page card is one third of the
--                                        SCROLLER's viewport, not of its own
--                                        parent column, which is the whole
--                                        distinction from a `percent` dim
--   * `UI.GridRow` + `gridSpan`  (§2.2) — a two-column spec table whose columns
--                                        line up across rows, headed by a cell
--                                        spanning both
--   * `UI.sensoryFeedback`       (§3.3) — the quality picker emits `select` and
--                                        the volume stepper emits `adjust` on
--                                        the presenter's feedback bus. Facet
--                                        still plays nothing; it says what
--                                        happened and a subscriber decides.

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
		local Facet = ctx.Facet
		local UI = Facet.UI
		local core = ctx.core
		local scope = core:scope("adaptive-controls")
		local conditions = Facet.adaptive.conditions(core, ctx.env, { scope = scope }) -- RR-8: six memos die with the fixture

		-- owner-held state (it must outlive the controls, and it is what a live
		-- orientation change has to preserve)
		local volume = core:signal(6)
		local brightness = core:signal(40)
		local quality = core:signal("balanced")
		local advancedOpen = core:signal(false)
		local progress = core:signal(0.35)

		local stepper = Facet.Controls.Stepper(core, {
			id = "Volume",
			label = "Volume",
			value = volume,
			min = 0,
			max = 10,
			step = 1,
		})
		local slider = Facet.Controls.Slider(core, {
			id = "Brightness",
			label = "Brightness",
			value = brightness,
			min = 0,
			max = 100,
			step = 5,
		})
		local picker = Facet.Controls.Picker(core, {
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
		local progressView = Facet.Controls.ProgressView(core, {
			id = "Download",
			label = "Download",
			value = progress,
			showValue = true,
		})
		local saveLabel = Facet.Controls.Label(core, { id = "SaveLabel", title = "Save changes" })
		local disclosure = Facet.Controls.DisclosureGroup(core, {
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

		--[[ ONE PICKER, TWO CONTAINERS — `iconOnly` and the VERTICAL PILL (D6).

			Both shipped with spec consumers only, so a device review had nothing to
			look at: `iconOnly = true` (every segment wears its semantic icon at every
			width, f1's top pill) and `axis = "y"` (the vertical RAIL, f1's left rail,
			which is content-sized with a 44px floor and is NOT the `inline` row list —
			`src/controls/picker.luau`'s D6 header states the distinction and
			`dump().verticalPill` reports it).

			THE TWO SHARE ONE SIGNAL, which is the claim worth putting on a screen: the
			difference between the pill and the rail is the CONTAINER and nothing else,
			so pressing a glyph in either moves both. The options carry both a `label`
			and an `icon` because `label` stays the semantic name whatever is drawn —
			it is what `dump().semanticText` announces and the only thing a non-visual
			consumer has — and the icons are SEMANTIC NAMES from the framework's own
			set, so a package that ships art for them paints it and one that declines
			draws the ASCII-safe glyph.

			`presentation = "segmented"` is DECLARED on both rather than left adaptive:
			`axis` is inert under the row list, so a strip that was allowed to flip to
			`inline` on a compact phone would be a rail that is sometimes not a rail —
			exactly the accepted-and-ignored shape this fixture is here to disprove. ]]
		local navSection = core:signal("browse")
		local NAV_OPTIONS = {
			{ value = "browse", label = "Browse", icon = "menu" },
			{ value = "compose", label = "Compose", icon = "edit" },
			{ value = "more", label = "More", icon = "more" },
		}
		local navPill = Facet.Controls.Picker(core, {
			id = "NavPill",
			options = NAV_OPTIONS,
			selected = navSection,
			presentation = "segmented",
			iconOnly = true,
			env = ctx.env,
		})
		local navRail = Facet.Controls.Picker(core, {
			id = "NavRail",
			options = NAV_OPTIONS,
			selected = navSection,
			presentation = "segmented",
			axis = "y",
			iconOnly = true,
			env = ctx.env,
		})
		-- the rail's neighbour is the READOUT, for the same reason the level-picker
		-- fixture prints `semanticText`: an icon-only control says nothing a bug
		-- report can quote, so the one string it publishes is printed where a human
		-- can check it names the segment that is actually lit
		local navReadout = scope:own(core:memo(function(use)
			return `Selected: {use(navSection)} — the pill and the rail share this one signal.`
		end))
		local navShapes = UI.VStack({
			id = "NavShapes",
			gap = 6,
			width = { type = "fill", weight = 1 },
			children = {
				UI.Text({ id = "NavHeading", text = "Icon segments, and the vertical rail", textSize = "caption" }),
				navPill.blueprint,
				UI.HStack({
					id = "NavRailRow",
					gap = "s",
					align = "start",
					width = { type = "fill", weight = 1 },
					children = {
						navRail.blueprint,
						UI.Text({
							id = "NavReadout",
							text = navReadout,
							textSize = "caption",
							role = "secondary",
							width = { type = "fill", weight = 1 },
						}),
					},
				}),
			},
		})

		-- the ACTION ROW is the ViewThatFits case: side by side when the container
		-- can hold it, stacked when it cannot. Measured, not guessed.
		local function actionButton(id: string, label: string, role: string?)
			return UI.Button({
				id = id,
				label = label,
				role = role,
				width = { type = "fill", weight = 1 },
				height = { type = "minMax", min = "targetSizes.minimum" },
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
					gap = "s",
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
				-- §3.3 `UI.sensoryFeedback`, on the two controls whose semantics are
				-- already in the closed twelve. `adjust` is the continuous verb
				-- (a stepper ticks; a subscriber rate-limits it — the framework does
				-- not), `select` the discrete one. The declaration rides `meta`, so
				-- the control's own blueprint is returned unchanged apart from it,
				-- and BOTH stay exactly the controls they were: nothing here plays a
				-- sound, a haptic or a particle, and nothing downstream of Facet
				-- does either unless a game subscribes the bus and decides to
				-- (`src/present/feedback.luau:4-5`).
				UI.sensoryFeedback(stepper.blueprint, { trigger = volume, event = "adjust" }),
				slider.blueprint,
				UI.sensoryFeedback(picker.blueprint, { trigger = quality, event = "select" }),
				UI.Divider({}),
				navShapes,
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
							textSize = "caption",
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
				UI.Button({ id = "TbBack", label = "◀", height = { type = "minMax", min = "targetSizes.minimum" } }),
				UI.Divider({ axis = "x" }),
				UI.Button({ id = "TbPlay", label = "Play", height = { type = "minMax", min = "targetSizes.minimum" } }),
				UI.Spacer({}),
				UI.Button({ id = "TbMore", label = "…", height = { type = "minMax", min = "targetSizes.minimum" } }),
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
		--[[ DELIBERATELY NARROWER THAN THE LABEL NEEDS — that is the demonstration,
			and it is why this stays a literal (wave TEN-FOOT, 2026-08-20). Spending
			`targetSizes.minimum` here was tried and measured WORSE: at 44 the
			fantasy-parchment frame no longer fitted on a compact phone either, so a
			metric name traded one recorded theme-inset yield for a wider one. A
			too-narrow button is more too-narrow at three metres; the theme ledger
			records which packages notice. ]]
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
					height = { type = "minMax", min = "targetSizes.minimum" },
				}),
				UI.Button({
					id = "CmpText",
					label = "Edit item",
					compactLabel = "Ed",
					width = compactWidth,
					height = { type = "minMax", min = "targetSizes.minimum" },
				}),
				UI.Button({
					id = "CmpIcon",
					label = "Edit item",
					compactLabel = { icon = "edit" },
					width = compactWidth,
					height = { type = "minMax", min = "targetSizes.minimum" },
				}),
				UI.Button({
					id = "CmpNone",
					label = "Edit item",
					width = compactWidth,
					height = { type = "minMax", min = "targetSizes.minimum" },
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
						UI.Text({ id = `Stat{i}`, text = `S{i}`, textSize = "caption" }),
						{ top = 4, bottom = 4, left = 6, right = 6 }
					),
					UI.Box({ id = `StatPlate{i}`, surface = "control" })
				)
			)
		end

		-- ===== THE ROUND-2 LAYOUT VOCABULARY (see the header) ================
		--
		-- ONE ROW PER PROP, and each one is chosen so the prop is VISIBLY doing
		-- something at a phone width AND at a desktop width — a demonstration that
		-- only fires at one end of the matrix teaches half the rule.
		--
		-- §2.6 `distribute`. Three hug-width markers naming the three tiers of the
		-- shrink row below. `spaceBetween` puts the leftover in the GAPS, so the
		-- first sits at the row's start edge and the last is flush to its end at
		-- every viewport — which is exactly the tab-bar case §2.6 was written for,
		-- and today's only alternative is hand-placed Spacers.
		local function marker(id: string, text: string)
			return UI.Text({ id = id, text = text, textSize = "caption", role = "secondary" })
		end
		-- ...AND IT WRAPS (O-21, 2026-08-15). `spaceBetween` distributes the
		-- leftover; it has nothing to say when there IS no leftover, and at +10/+14
		-- these three markers measure past a phone's HUD column — `Essential` was
		-- painting up to 92px off the right screen edge, which is a label naming a
		-- tier that a player cannot read. Wrapping costs the demonstration nothing:
		-- the row still distributes at every width where the three fit, which is
		-- every viewport at the default preference.
		local vocabLegend = UI.HStack({
			id = "Legend",
			distribute = "spaceBetween",
			wrap = true,
			width = { type = "fill", weight = 1 },
			children = {
				marker("LegendLow", "Optional"),
				marker("LegendMid", "Useful"),
				marker("LegendHigh", "Essential"),
			},
		})
		-- §2.4 the shrink pass, and §2.1 `lineAlign` riding the same row.
		--
		-- 140 x 3 + two 6px gaps = 432, which FITS the HUD column on a desktop and
		-- does NOT fit it on a phone — deliberately, because "what happens when the
		-- main axis is short" is the entire feature and a row that always fits
		-- would never once execute it. When it is short:
		--   * `Optional` is tier -1, so it gives way FIRST, down to its declared
		--     24px floor (`minMax.min`, the first rung of the floor stack);
		--   * `Useful` is tier 0 and only starts giving once tier -1 is spent;
		--   * `Essential` declares NO `shrinkWeight`, and 0 is the default, so it
		--     is rigid at every width — Roblox's own `UIFlexMode.None`.
		-- The narrowest column any swept viewport gives this row is 280px and the
		-- row's total floor is 24 + 0 + 140 + 12 = 176, so it absorbs its deficit
		-- everywhere rather than falling through to the overflow diagnostic.
		--
		-- `align = "start"` on the row is what makes `lineAlign = "end"` legible:
		-- the line is 24px tall (the two full-height bars set it) and Essential is
		-- 16px, so without the per-child override it would sit at the top with its
		-- siblings. `lineAlign` is the shared BOX prop §2.1 promoted out of the
		-- overloaded word `align`, and a stack is the only parent that reads it.
		local function bar(id: string, extra: { [string]: any })
			local props: { [string]: any } = {
				id = id,
				surface = "control",
				width = { type = "fixed", px = 140 },
				height = { type = "fixed", px = 24 },
			}
			for key, value in extra do
				props[key] = value
			end
			return UI.Box(props)
		end
		local vocabShrink = UI.HStack({
			id = "Shrink",
			gap = 6,
			align = "start",
			width = { type = "fill", weight = 1 },
			children = {
				bar("VocabOptional", {
					width = { type = "minMax", min = 24, preferred = 140 },
					shrinkWeight = 1,
					layoutPriority = -1,
				}),
				bar("VocabUseful", { shrinkWeight = 1 }),
				bar("VocabEssential", { height = { type = "fixed", px = 16 }, lineAlign = "end" }),
			},
		})
		-- §2.5 `containerRelativeFrame`. A paging card: one of three across the
		-- SCROLLER's viewport, gutters included. The card is a child of this HUD
		-- column, and on a desktop the column is about half the scroller wide — so
		-- a `percent` dim would have measured against the column and produced a
		-- different number. That difference IS the feature, and it is the thing the
		-- headless case in tests/examples_gallery.spec.luau asserts.
		local vocabPage = UI.containerRelativeFrame(
			UI.Box({ id = "Page", surface = "control", height = { type = "fixed", px = 28 } }),
			{ axis = "horizontal", count = 3, span = 1, spacing = 8 }
		)
		-- §2.2 `UI.GridRow` + `gridSpan`. Row mode is selected by the CHILDREN, not
		-- by a mode prop: this Grid declares GridRows, so its columns are the widest
		-- natural cell per column across every row rather than one shared width, and
		-- the two `Spec*Key` cells line up under each other however long their values
		-- are. The header cell spans both columns and contributes to neither
		-- column's maximum.
		local function specCell(id: string, text: string, extra: { [string]: any }?)
			local props: { [string]: any } = { id = id, text = text, textSize = "caption" }
			for key, value in extra or {} do
				props[key] = value
			end
			return UI.Text(props)
		end
		local vocabSpecs = UI.Grid({
			id = "Specs",
			gap = 6,
			width = { type = "fill", weight = 1 },
			children = {
				UI.GridRow({
					id = "SpecHead",
					-- `fill` IS LOAD-BEARING, not decoration: a hug cell would be its own
					-- 60px natural whether it spanned one column or two, so the span
					-- would be accepted and invisible — the exact "assertion its own
					-- starting value already satisfies" shape. Filling makes the cell
					-- take the two columns AND the gap between them, which is the
					-- arithmetic §2.2 specifies and the headless case asserts.
					children = {
						specCell("SpecTitle", "Row grid", {
							gridSpan = 2,
							width = { type = "fill", weight = 1 },
						}),
					},
				}),
				UI.GridRow({
					id = "SpecA",
					children = {
						specCell("SpecAKey", "Columns", { role = "secondary" }),
						specCell("SpecAVal", "align"),
					},
				}),
				UI.GridRow({
					id = "SpecB",
					children = {
						specCell("SpecBKey", "Span", { role = "secondary" }),
						specCell("SpecBVal", "the header"),
					},
				}),
			},
		})

		local hudColumn = UI.VStack({
			id = "Hud",
			gap = "s",
			width = { type = "fill", weight = 1 },
			children = {
				UI.Text({ id = "HudHeading", text = "Status", textSize = "control" }),
				UI.Divider({}),
				toolbar,
				compactLadder,
				progressView.blueprint,
				saveLabel.blueprint,
				media,
				-- the dense readout field
				UI.Grid({
					id = "Stats",
					-- A DENSITY FLOOR for the readout field, measured and kept 2026-08-21:
					-- `"intrinsic"` sizes these to the widest `S12` glyph run, which re-columns the
					-- field so short that the page stops overflowing its scroller at all — and this
					-- fixture's §2.5 case is about what a scroller's viewport measures.
					minColumnWidth = 48,
					gap = "xs",
					width = { type = "fill", weight = 1 },
					children = hudTiles,
				}),
				-- a dense tile grid: fill cells occupy their derived columns (A-LV1)
				UI.Grid({
					id = "Tiles",
					-- NOT `"intrinsic"`: every cell here is `fill` width, and a fill child cannot
					-- express an intrinsic minimum (it measures to whatever it is offered), so the
					-- grid would fall back to ONE LANE and the thing this fixture demonstrates —
					-- fill cells occupying their derived columns — would have nothing to show.
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
				-- the round-2 layout vocabulary, built above
				UI.Divider({}),
				UI.Text({ id = "VocabHeading", text = "Layout vocabulary", textSize = "control" }),
				vocabLegend,
				vocabShrink,
				vocabPage,
				vocabSpecs,
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
			-- THEME-OPT-OUT: this gutter decides the usable width of every control row
			-- below it. MEASURED with `padding = "m"`: on a 320x640 phone under glossy-mobile
			-- and glossy-touch the theme's larger step narrows the body to 242px and the
			-- Slider row overflows by 4px AT +0 — a default-text-size regression on a shipped
			-- package. The gutter waits on a control row that can give way at that width.
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
							gap = "m",
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
				navPill.dispose()
				navRail.dispose()
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
				-- the `select` half of §3.3's declaration, drivable without a pointer:
				-- moving `quality` is what the picker's own press moves, so the
				-- scripted step and the player's press take the identical route
				cycleQuality = function()
					quality:set(if quality:get() == "fidelity" then "balanced" else "fidelity")
					return quality:get()
				end,
				-- the D6 pair moves through the ONE signal they share, which is the
				-- whole claim: a step that drove the pill would prove nothing about
				-- the rail, and this drives neither control — it drives the value
				cycleNav = function()
					navSection:set(if navSection:get() == "browse" then "more" else "browse")
					return navSection:get()
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
					-- the D6 pair, so a device pass can read the two facts that tell
					-- the shapes apart rather than judging them by eye: `iconOnly` on
					-- both, and `verticalPill` TRUE on the rail and false on the pill
					navPill = navPill.dump(),
					navRail = navRail.dump(),
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
