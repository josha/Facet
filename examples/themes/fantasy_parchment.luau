--!strict

local fantasy_parchment = {}

fantasy_parchment.id = "fantasy-parchment"
fantasy_parchment.displayName = "Fantasy Parchment"

fantasy_parchment.themeClasses = table.freeze({ "palette", "metrics", "font", "assets" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

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

		success = rgb(74, 106, 44),
		onSuccess = rgb(252, 244, 224),
		warning = rgb(190, 134, 32),
		onWarning = rgb(38, 28, 16),
	},
	extra = {
		control = rgb(214, 194, 156),
		controlHover = rgb(226, 208, 172),
		controlPressed = rgb(198, 176, 138),
		controlSelected = rgb(212, 186, 132),
		contentSecondary = rgb(110, 92, 66),
		hairline = rgb(88, 68, 44),

		focusGlow = rgb(214, 154, 46),
		hairlineOpacity = 0.72,
		scrimOpacity = 0.5,
		disabledContentOpacity = 0.45,
	},
}

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

		success = rgb(132, 158, 74),
		onSuccess = rgb(32, 22, 10),
		warning = rgb(206, 152, 58),
		onWarning = rgb(32, 22, 10),
	},
	extra = {
		control = rgb(86, 66, 44),
		controlHover = rgb(102, 80, 54),
		controlPressed = rgb(66, 50, 34),
		controlSelected = rgb(112, 86, 44),
		contentSecondary = rgb(196, 176, 142),
		hairline = rgb(226, 200, 150),

		focusGlow = rgb(248, 196, 96),
		hairlineOpacity = 0.7,
		scrimOpacity = 0.55,
		disabledContentOpacity = 0.45,
	},
}

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

		preload = "lazy",
		fallback = "native",
	},

	parchment_slider_track = {
		contentId = "rbxassetid://133629068271978",
		sliceCenter = { x0 = 8, y0 = 8, x1 = 88, y1 = 12 },
		sliceScale = 1,
		preload = "lazy",
		fallback = "native",
	},

	parchment_slider_thumb = {
		contentId = "rbxassetid://102024273231445",
		preload = "lazy",
		fallback = "native",
	},

	parchment_badge = {
		contentId = "rbxassetid://103212793200116",
		preload = "lazy",
		fallback = "native",
	},
}

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

		metrics = GENERATED.metrics,
		chrome = {

			panel = {
				kind = "nineSlice",
				asset = "parchment_panel",
				contentInsets = { top = 18, right = 18, bottom = 18, left = 18 },
				fallback = "native",

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

			focus = {
				kind = "glow",
				color = "$FocusGlow",

				blurRadius = { scale = 0, offset = 26 },
				transparency = 0.25,
				zIndex = -1,
			},

			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },

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
