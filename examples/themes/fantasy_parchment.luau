--!strict
-- "FANTASY PARCHMENT" — the stage's primary proof theme (ADR-0019 §6) and the
-- worked example `docs/guide/09-custom-themes.md` walks through line by line.
--
-- Written as a CLEAN CONSUMER: everything here goes through the public
-- `Facet.themes` surface (define + neutralPackage as the base) — no internal
-- imports, no screen-specific branches. A game team with only the public docs
-- can reproduce this file, which is the acceptance claim it exists to prove.
--
-- The art is original and repository-owned: three procedurally generated
-- nine-slice PNGs (assets/themes/fantasy-parchment/ — provenance.md records the
-- generator, seed and reproduction steps; upload-manifest.json records the
-- content IDs used here). Another project uploads the same PNGs under its own
-- account and substitutes its IDs.
--
-- Two themes prove in-package theming: "Daylight" (ink on sunlit paper, the
-- default) and "Candlelight" (firelit study). Interaction states are TINTS over
-- one base image per slot — hover lightens, press darkens, disabled dims with
-- the text — so the whole skin ships on three small assets. Every pair below
-- clears the 4.5:1 contrast gate (checked at define time; verified 2026-07-25:
-- weakest pair is Candlelight accent at 6.48:1).
--
-- TWO HALVES, ONE OWNER EACH (ADR-0019 §3). The METRICS section below sits in a
-- marker region and is GENERATOR-OWNED: the DataModel theme sheet is where a
-- designer retunes spacing, type and control sizes, and `theme_sync` writes
-- those edits back here. Never hand-edit inside the markers — the freshness gate
-- fails the build when the file and the sheet disagree, naming every token that
-- drifted. Everything else in this file — the palette, the chrome recipes, the
-- asset table — is hand-authored and `theme_sync` never touches it.

local fantasy_parchment = {}

fantasy_parchment.id = "fantasy-parchment"
fantasy_parchment.displayName = "Fantasy Parchment"
-- the four theme classes the stage tracks; this package carries all four
fantasy_parchment.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

-- Daylight: iron-gall ink on sunlit paper. The accent is the illuminator's
-- burnished gold-brown, dark enough to carry cream text.
local DAYLIGHT = {
	colors = {
		surface = rgb(226, 210, 176),
		surfaceStrong = rgb(238, 226, 198),
		content = rgb(52, 40, 26),
		contentStrong = rgb(38, 28, 16),
		accent = rgb(122, 72, 26),
		onAccent = rgb(252, 244, 224),
		danger = rgb(140, 36, 28),
		onDanger = rgb(255, 242, 232),
	},
	extra = {
		control = rgb(214, 194, 156),
		controlHover = rgb(226, 208, 172),
		controlPressed = rgb(198, 176, 138),
		controlSelected = rgb(212, 186, 132),
		contentSecondary = rgb(110, 92, 66),
		hairline = rgb(88, 68, 44),
		-- FOCUS GLOW (director review 2026-07-25: the blue selection ring "looks
		-- bad" on parchment). A per-theme role, declared here rather than in the
		-- recipe because a colour is palette and palette is per theme — the same
		-- place and the same reason `chromeGradient` sits in `extra`.
		--
		-- Daylight: burnished gold, a step brighter and more saturated than the
		-- accent. The accent itself (a dark gold-brown, chosen to carry cream
		-- text) is too dark to read as a HALO against sunlit paper — a glow has to
		-- out-value the surface it sits on, not match it.
		focusGlow = rgb(214, 154, 46),
		hairlineOpacity = 0.72,
		scrimOpacity = 0.5,
		disabledContentOpacity = 0.45,
	},
}

-- Candlelight: the same study after dark — warm umber surfaces, cream ink,
-- firelit gold accent carrying near-black text.
local CANDLELIGHT = {
	colors = {
		surface = rgb(48, 36, 26),
		surfaceStrong = rgb(72, 55, 38),
		content = rgb(242, 228, 198),
		contentStrong = rgb(252, 244, 224),
		accent = rgb(196, 148, 62),
		onAccent = rgb(32, 22, 10),
		danger = rgb(150, 40, 30),
		onDanger = rgb(255, 242, 232),
	},
	extra = {
		control = rgb(86, 66, 44),
		controlHover = rgb(102, 80, 54),
		controlPressed = rgb(66, 50, 34),
		controlSelected = rgb(112, 86, 44),
		contentSecondary = rgb(196, 176, 142),
		hairline = rgb(226, 200, 150),
		-- Candlelight: warm amber firelight, pushed brighter still because the
		-- surfaces around it are dark umber — the same role, re-picked for its own
		-- palette rather than inherited, which is the whole point of a per-theme token.
		focusGlow = rgb(248, 196, 96),
		hairlineOpacity = 0.7,
		scrimOpacity = 0.55,
		disabledContentOpacity = 0.45,
	},
}

-- Slice geometry per assets/themes/fantasy-parchment/upload-manifest.json:
-- SliceCenter = Rect(border, border, size - border, size - border), scale 1.
-- Control borders are 16px so both borders fit a 46px-tall control.
local ASSETS = {
	parchment_panel = {
		contentId = "rbxassetid://78012779616687",
		sliceCenter = { x0 = 40, y0 = 40, x1 = 104, y1 = 104 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	parchment_button = {
		contentId = "rbxassetid://87220434497053",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,
		preload = "install",
		fallback = "native",
	},
	parchment_field = {
		contentId = "rbxassetid://73053023436561",
		sliceCenter = { x0 = 16, y0 = 16, x1 = 48, y1 = 48 },
		sliceScale = 1,
		-- lazy: field skin loads when a screen with a field first mounts
		preload = "lazy",
		fallback = "native",
	},
	-- VALUE-CONTROL ART (director review 2026-07-25: "just changing the colour
	-- isn't enough"). The rail STRETCHES, so it is a nine-slice: 96x20 with an
	-- 8px border, which keeps its carved end-caps intact at any track width.
	parchment_slider_track = {
		contentId = "rbxassetid://133629068271978",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 88, y1 = 12 },
		sliceScale = 1,
		preload = "lazy",
		fallback = "native",
	},
	-- The thumb does NOT stretch — it is a 28x28 token — so it is painted
	-- WHOLE. Slicing it would smear its centre pixel across the jewel.
	parchment_slider_thumb = {
		contentId = "rbxassetid://102024273231445",
		preload = "lazy",
		fallback = "native",
	},
	-- The counter seal behind a badge's number, also a whole 28x28 token.
	parchment_badge = {
		contentId = "rbxassetid://103212793200116",
		preload = "lazy",
		fallback = "native",
	},
}

-- ===== METRICS — the theme_sync region ====================================
--
-- GENERATOR-OWNED. Regenerate it from a Style-Editor session with:
--   lune run tools/lune/theme_sync_cli -- \
--     --dump <dump.json> --package examples/themes/fantasy_parchment.luau
-- and check it with the same command plus `--check` (exit 1 on drift, naming
-- the tokens that moved). `definition()` below consumes exactly this table, so
-- there is never a second hand-edited metric source.
--
-- What the numbers say, for a reader who will never open the Style Editor:
-- Fondamento (a Roblox-shipped calligraphic family — fantasy-appropriate
-- without bundling a font) at 1.35 line height, because a calligraphic face
-- needs more air than a UI sans; a rounder 4/8/16/26/42 spacing rhythm than
-- Studio Neutral's; taller controls (38/46/58) because the carved border needs
-- shoulder room; and per-slot insets that each nine-slice recipe's own
-- contentInsets are ADDED to, so content always clears the painted border.
--
-- ...and `controls.progress.circularSize` / `circularThickness` / `spinnerDotSize`
-- (director round 2026-08-14), which are the two theme-sized indicators: a 30px
-- ring drawn with a 3px stroke and a 9px dot. This skin is a QUILL — the thinnest
-- ink in the corpus over the largest paper — so it takes a mid-sized ring and the
-- second-thinnest stroke, where its ornate sibling takes 44/8 on the same shapes.
-- Left unauthored both packages resolved to the identical 26/4, because they
-- share a space scale and the fill-in reads the space scale: two packages that
-- look nothing alike were drawing the same ring.
local GENERATED: any = {
	-- theme_sync:begin metrics
	metrics = {
		controlSizes = {
			compact = {
				height = 38,
				iconSize = 18,
				paddingX = 14,
			},
			large = {
				height = 58,
				iconSize = 26,
				paddingX = 22,
			},
			regular = {
				height = 46,
				iconSize = 22,
				paddingX = 18,
			},
		},
		controls = {
			button = {
				padding = 12,
			},
			image = {
				defaultSize = 48,
			},
			label = {
				-- THEME-OPT-OUT: a theme package's own metrics.controls.<family>
				-- field is validated isFiniteNumber-only (package.luau's
				-- CONTROL_FAMILIES check) — it cannot take a theme-metric NAME
				-- string like "tight", the same reason default_style.luau's own
				-- controls.label.gap stays a raw literal (ADR-0047)
				gap = 6,
			},
			popup = {
				triggerHeight = 40,
			},
			progress = {
				circularSize = 30,
				circularThickness = 3,
				rowMinHeight = 20,
				spinnerDotSize = 9,
				trackHeight = 6,
			},
			rowActions = {
				buttonMinWidth = 64,
				buttonPad = 8,
				editAffordance = 28,
			},
			slider = {
				railHeight = 6,
				readoutMinWidth = 40,
				thumbSize = 20,
			},
			stepper = {
				valueMinWidth = 32,
			},
			table = {
				cellTextSize = 15,
				editToggleHeight = 24,
				editToggleInset = 2,
				editTogglePadding = 6,
				editToggleWidth = 56,
				ghostHeight = 26,
				ghostStackHeight = 32,
				ghostStackWidth = 186,
				ghostWidth = 180,
				headerHeight = 28,
				indicatorThickness = 2,
				rowGap = 2,
				sortMarkMargin = 14,
				sortMarkTextSize = 11,
			},
			textInput = {
				clearSize = 28,
				fieldHeight = 44,
				padding = 12,
			},
			toggle = {
				minHeight = 28,
				trackInset = 12,
				trackWidth = 44,
			},
		},
		insets = {
			control = {
				bottom = 4,
				left = 8,
				right = 8,
				top = 4,
			},
			divider = {
				bottom = 0,
				left = 0,
				right = 0,
				top = 0,
			},
			field = {
				bottom = 4,
				left = 8,
				right = 8,
				top = 4,
			},
			panel = {
				bottom = 8,
				left = 8,
				right = 8,
				top = 8,
			},
			scrollbar = {
				bottom = 0,
				left = 0,
				right = 0,
				top = 0,
			},
			selection = {
				bottom = 4,
				left = 6,
				right = 6,
				top = 4,
			},
		},
		motion = {
			fast = 0.14,
			normal = 0.24,
		},
		radii = {
			control = 6,
			panel = 10,
			pill = 999,
		},
		space = {
			l = 26,
			m = 16,
			s = 8,
			xl = 42,
			xs = 4,
		},
		strokes = {
			hairline = 1,
		},
		targetSizes = {
			minimum = 44,
		},
		typography = {
			body = {
				font = {
					family = "rbxasset://fonts/families/Fondamento.json",
					style = "Normal",
					weight = "Regular",
				},
				lineHeight = 1.35,
				size = 16,
			},
			caption = {
				font = {
					family = "rbxasset://fonts/families/Fondamento.json",
					style = "Normal",
					weight = "Regular",
				},
				lineHeight = 1.35,
				size = 12,
			},
			control = {
				font = {
					family = "rbxasset://fonts/families/Fondamento.json",
					style = "Normal",
					weight = "Regular",
				},
				lineHeight = 1.35,
				size = 17,
			},
			heading = {
				font = {
					family = "rbxasset://fonts/families/Fondamento.json",
					style = "Normal",
					weight = "Regular",
				},
				lineHeight = 1.35,
				size = 22,
			},
			label = {
				font = {
					family = "rbxasset://fonts/families/Fondamento.json",
					style = "Normal",
					weight = "Regular",
				},
				lineHeight = 1.35,
				size = 14,
			},
			title = {
				font = {
					family = "rbxasset://fonts/families/Fondamento.json",
					style = "Normal",
					weight = "Regular",
				},
				lineHeight = 1.35,
				size = 28,
			},
		},
	},
	-- theme_sync:end metrics
}

function fantasy_parchment.definition(themes: any): any
	return {
		-- start from the library's own package and override what the theme
		-- means to change; core roles added by future Facet versions are then
		-- inherited through a diagnosed upgrade instead of a copied sheet
		base = themes.neutralPackage(),
		identity = {
			id = fantasy_parchment.id,
			displayName = fantasy_parchment.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Daylight",
			themes = {
				{ name = "Daylight", colors = DAYLIGHT.colors, extra = DAYLIGHT.extra },
				{ name = "Candlelight", colors = CANDLELIGHT.colors, extra = CANDLELIGHT.extra },
			},
		},
		-- the generator-owned region above; a designer's Style-Editor session
		-- lands here through `theme_sync`, never through a hand edit
		metrics = GENERATED.metrics,
		chrome = {
			-- the ink rule sits ~14px inside the panel art's 40px border; 18px
			-- of content inset clears it at every panel size
			panel = {
				kind = "nineSlice",
				asset = "parchment_panel",
				contentInsets = { top = 18, right = 18, bottom = 18, left = 18 },
				fallback = "native",
				-- a sheet of vellum lying ON the desk, not printed into it
				-- (director review 2026-07-25: "buttons should have shadows").
				-- Adapter-owned depth: ::UIShadow rules are inert (m7), so this
				-- rides the bespoke UIShadow machinery behind its capability probe.
				shadow = "raised",
			},
			control = {
				kind = "nineSlice",
				asset = "parchment_button",
				contentInsets = { top = 8, right = 12, bottom = 8, left = 12 },
				fallback = "native",
				shadow = "raised",
			},
			field = {
				kind = "nineSlice",
				asset = "parchment_field",
				contentInsets = { top = 8, right = 12, bottom = 8, left = 12 },
				fallback = "native",
			},
			-- FOCUS IS A GLOW ON THIS SKIN, not a ring. Everything else here is
			-- soft and painted, and a 2px hard stroke read as a UI element that
			-- had wandered in from another game. The colour is the per-theme
			-- `focusGlow` role above, so Daylight and Candlelight each get their
			-- own; the ten-foot profile scales the blur up and the transparency
			-- down automatically (chrome_slots.FOCUS_TEN_FOOT).
			focus = {
				kind = "glow",
				color = "$FocusGlow",
				-- 26px of blur on a 46px control is a halo that clears the
				-- control's own edge without swallowing its neighbours at the 8px
				-- `s` gap this theme uses between rows
				blurRadius = { scale = 0, offset = 26 },
				transparency = 0.25,
				zIndex = -1,
			},
			-- ink-wash fills, no imagery: selection, dividers and scrollbars
			-- read best as flat paint on this material
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
			-- the carved rail and its jewelled thumb. `sliced = false` on the
			-- thumb is the whole-image treatment; the slot would have defaulted
			-- to it anyway, and saying so keeps the recipe readable.
			sliderTrack = {
				kind = "nineSlice",
				asset = "parchment_slider_track",
				contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
				fallback = "native",
			},
			sliderThumb = {
				kind = "nineSlice",
				asset = "parchment_slider_thumb",
				sliced = false,
				contentInsets = { top = 0, right = 0, bottom = 0, left = 0 },
				fallback = "native",
			},
			-- the counter seal. Its 5px inset is what pulls the number off the
			-- seal's raised rim — the lifted label is positioned by exactly this.
			badge = {
				kind = "nineSlice",
				asset = "parchment_badge",
				sliced = false,
				contentInsets = { top = 5, right = 5, bottom = 5, left = 5 },
				fallback = "native",
			},
		},
		assets = ASSETS,
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function fantasy_parchment.build(themes: any): (any, any)
	return themes.define(fantasy_parchment.definition(themes))
end

return fantasy_parchment
