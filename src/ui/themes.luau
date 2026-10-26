--!strict
local segmentMetrics = require("./segment_metrics")
local ComposeTypes = require("../vendor/compose/core")
local resolveIcon = require("./theme_icons")
local ThemeTypes = require("./theme_types")
local Engine = require("./engine_types")
local themeDistance = require("./theme_distance")
local support = require("./theme_support")
local ruleKit = require("./theme_rule_kit")
local defineThemes = require("./theme_define")
local createStyleSheet = require("./theme_stylesheet")
local skin = require("./theme_skin")
export type ThemePackage = ThemeTypes.ThemePackage
export type ThemeDefinition = ThemeTypes.ThemeDefinition
export type ThemeOptions = ThemeTypes.ThemeOptions
export type SkinOptions = ThemeTypes.SkinOptions
export type Themes = ThemeTypes.Themes

type NativeRule = ruleKit.NativeRule

local themes = {}
local contrast, copy, merge = support.contrast, support.copy, support.merge
themes.SCHEMA = "facet-theme/2"
themes.TYPE_ROLES = table.freeze({ "caption", "label", "body", "heading", "title", "control", "strong", "numeral" })
themes.REQUIRED_TYPE_ROLES = themes.TYPE_ROLES
local AVATAR_BACKGROUNDS: { [string]: string } = table.freeze({
	surface = "content",
	surfaceStrong = "content",
	control = "content",
	contentStrong = "surface",
	accent = "onAccent",
	success = "onSuccess",
	warning = "onWarning",
	danger = "onDanger",
})

local function rgb(r: number, g: number, b: number): ThemeTypes.RGB
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local neutral: ThemeTypes.ThemePackage = {
	schema = themes.SCHEMA,
	identity = { id = "facet-neutral", displayName = "Facet Neutral", version = "2.0.0", schemaVersion = themes.SCHEMA },
	style = {
		defaultTheme = "Dark",
		themes = {
			{
				name = "Dark",
				colors = {
					surface = rgb(18, 20, 26),
					surfaceStrong = rgb(28, 31, 40),
					content = rgb(236, 239, 245),
					contentStrong = rgb(250, 251, 253),
					accent = rgb(44, 98, 210),
					onAccent = rgb(255, 255, 255),
					danger = rgb(176, 42, 42),
					onDanger = rgb(255, 255, 255),
					success = rgb(29, 122, 66),
					onSuccess = rgb(255, 255, 255),
					warning = rgb(212, 154, 28),
					onWarning = rgb(26, 20, 6),
				},
				extra = {
					control = rgb(41, 45, 58),
					controlHover = rgb(49, 54, 69),
					controlPressed = rgb(34, 37, 48),
					controlSelected = rgb(45, 58, 92),
					contentSecondary = rgb(158, 165, 182),
					hairline = rgb(255, 255, 255),
					hairlineOpacity = 0.92,
					disabledContentOpacity = 0.4,
					scrimOpacity = 0.45,
				},
			},
			{
				name = "Light",
				colors = {
					surface = rgb(242, 244, 248),
					surfaceStrong = rgb(255, 255, 255),
					content = rgb(28, 32, 41),
					contentStrong = rgb(12, 14, 20),
					accent = rgb(44, 98, 210),
					onAccent = rgb(255, 255, 255),
					danger = rgb(185, 28, 28),
					onDanger = rgb(255, 255, 255),
					success = rgb(21, 107, 58),
					onSuccess = rgb(255, 255, 255),
					warning = rgb(224, 166, 32),
					onWarning = rgb(28, 22, 6),
				},
				extra = {
					control = rgb(228, 231, 238),
					controlHover = rgb(219, 223, 233),
					controlPressed = rgb(206, 211, 224),
					controlSelected = rgb(205, 219, 245),
					contentSecondary = rgb(90, 98, 114),
					hairline = rgb(10, 12, 18),
					hairlineOpacity = 0.92,
					disabledContentOpacity = 0.4,
					scrimOpacity = 0.45,
				},
			},
		},
	},
	metrics = {
		typography = {},
		space = { xs = 4, s = 8, m = 16, l = 24, xl = 40, tight = 6, gutter = 8 },
		radii = { control = 8, panel = 12, pill = 999, tab = 999 },
		strokes = { hairline = 1 },
		targetSizes = { minimum = 44, inline = 24, thumb = 70, thumbLarge = 120 },
		controlSizes = {
			compact = { height = 36, paddingX = 8, iconSize = 16 },
			regular = { height = 44, paddingX = 12, iconSize = 20 },
			large = { height = 56, paddingX = 16, iconSize = 24 },
		},
		motion = {
			typewriter = { grapheme = 0.035, pause = 0 },
			fast = 0.12,
			normal = 0.2,
			press = 0.08,
			hover = 0.15,
			reducedFade = 0.15,
			revealFadeShare = 0.5,
			presentFadeIn = 0.6,
			presentFadeOut = 0.5,
			unfoldStart = 0.25,
			restLimit = 0.25,
			popover = { enter = 0.15, exit = 0.1 },
			dialog = { enter = 0.2, exit = 0.15 },
			reveal = { enter = 0.25, exit = 0.2 },
			sheet = { enter = 0.3, exit = 0.2 },
			toast = { enter = 0.2, exit = 0.2 },
			radial = { enter = 0.2, exit = 0.12, slot = 0.16 },
			durations = {
				pressLift = 0.1,
				zoom = 0.22,
				travel = 0.3,
				travelFade = 0.16,
				travelStagger = 0.045,
				sequence = 0.3,
				countUp = 0.3,
				shake = 0.3,
				tabFade = 0.2,
				pageTurn = 0.65,
				popoverSheetExit = 0.2,
				rowDeparture = 0.24,
				cardFade = 0.15,
				regionPop = 0.15,
				fieldReject = 0.24,
				buttonPop = 0.45,
				scrollReveal = 0.25,
				focusPulse = 1,
				busyLoop = 1,
				progressLoop = 1,
				spinnerLoop = 1.4,
				glide = 0.22,
				trailDelay = 0.3,
				trailSettle = 0.35,
			},
			springs = {
				snappy = { period = 0.2, damping = 1 },
				quick = { period = 0.18, damping = 1 },
				travel = { period = 0.18, damping = 1 },
				control = { period = 0.25, damping = 1 },
				move = { period = 0.3, damping = 1 },
				sheet = { period = 0.4, damping = 1 },
				flick = { period = 0.3, damping = 0.8 },
			},
			materialize = {
				anchored = 0.9,
				menu = 0.96,
				modal = 0.94,
				branch = 0.3,
				lift = 1.04,
				radialSpread = 0.2,
				popOvershoot = 0.25,
				popDecay = 3,
				shakeCycles = 3,
			},
			scales = { travelLift = 1.08 },
			distances = { menuSlide = 32, parallax = 0.3, dim = 0.1, travelArc = 48, shakeAngle = 6 },
			easing = {
				present = "outCubic",
				fade = "outQuad",
				trail = "linear",
				zoom = "outCubic",
				travel = "outCubic",
				sequence = "outCubic",
				countUp = "outCubic",
				shake = "linear",
			},
			styles = { paint = "Quad", scroll = "Quad", page = "Cubic", fling = "Quint", pulse = "Sine" },
			fling = { friction = 3, maxSpeed = 4000, projection = 0.08, bounceSpeed = 800 },
		},
		iconSizes = { small = 16, medium = 20, large = 24 },
		controls = {
			navigationBack = { swipeEdge = 24 },
			button = { captionStroke = 1.5, captionStrokeOpacity = 0.7 },
			tabBottomTrack = { height = 64, sideInset = 16, bottomInset = 12, radius = 20, contentGap = 8 },
			tabRailTrack = { sideInset = 8, topInset = 8, bottomInset = 8, radius = 16 },
			tabMark = { width = 20, height = 4, gap = 4, radius = 2 },
			tabRailSelection = { insetX = 8, insetY = 4, radius = 8 },
			zoom = { stepRatio = 1.25, panSpeed = 480, panStep = 48, doubleTapSeconds = 0.35, doubleTapDistance = 12 },
			progress = {
				trackHeight = 6,
				minTrackWidth = 64,
				circularSize = 32,
				circularThickness = 3,
				spinnerDotSize = 4,
			},
			image = { defaultSize = 48 },
			alert = { maxWidth = 560 },
			popup = { panelWidth = 360 },
			typography = { preferredSizeStep = 2, minimumSize = 14 },
			dialog = { wideWidth = 800 },
			snackbar = { maxWidth = 480 },
			radial = { narrow = 48, regular = 64, wide = 88 },
		},
	},
	chrome = {},
	assets = {},
	icons = {},
	rules = {},
}
local typographySizes: { [string]: number } =
	{ caption = 14, label = 15, body = 16, heading = 20, title = 24, control = 18, strong = 16, numeral = 18 }
for role, size in typographySizes do
	neutral.metrics.typography[role] = {
		size = size,
		font = {
			family = "BuilderSans",
			weight = if role == "heading"
					or role == "title"
					or role == "numeral"
				then "Bold"
				elseif role == "strong" then "SemiBold"
				else "Regular",
			style = "Normal",
		},
		lineHeight = 1.2,
	}
end

function themes.neutralPackage(): ThemeTypes.ThemePackage
	return copy(neutral)
end

themes.forDistance = themeDistance(neutral)

local definitions = defineThemes(neutral, themes.SCHEMA, themes.TYPE_ROLES)
themes.define = definitions.define
themes.checkCoverage = definitions.checkCoverage

themes.resolveIcon = resolveIcon

local function color(types: Engine.RobloxTypes, value: ThemeTypes.RGB | Color3?): Color3?
	if type(value) == "table" and value.r ~= nil then
		return types.Color3.new(value.r, value.g, value.b)
	end
	return value :: Color3?
end

local paint: support.Paint = {
	color = color,
	white = function(types: Engine.RobloxTypes): Color3
		return types.Color3.new(1, 1, 1)
	end,
}

local SEGMENT_INSET = segmentMetrics.inset

local function rulesFor(package: ThemeTypes.ThemePackage, selected: string?, types: Engine.RobloxTypes): { NativeRule }
	local kit = ruleKit(package, selected, types, neutral, paint)
	local extra, source, c, f, rule = kit.extra, kit.source, kit.c, kit.f, kit.rule
	local resolved = kit.resolved
	rule("ScrollingFrame", {
		VerticalScrollBarInset = types.Enum.ScrollBarInset.Always,
		HorizontalScrollBarInset = types.Enum.ScrollBarInset.ScrollBar,
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = c("contentSecondary"),
		ScrollBarImageTransparency = 0.4,
	})
	rule(".facet-layout", { BackgroundTransparency = 1 })
	rule(".facet-text", {
		TextColor3 = c("content"),
		FontFace = f(package.metrics.typography.body.font),
		TextSize = package.metrics.typography.body.size,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
	})
	for _, role in themes.TYPE_ROLES do
		local typography = package.metrics.typography[role] or neutral.metrics.typography[role]
		rule(".facet-type-" .. role, {
			FontFace = f(typography.font),
			TextSize = typography.size,
			LineHeight = typography.lineHeight or 1.2,
			TextColor3 = if role == "caption" then c("contentSecondary") else nil,
		})
	end
	rule(".facet-validation", { TextColor3 = c("danger"), TextSize = package.metrics.typography.caption.size })
	rule(".facet-secondary", { TextColor3 = c("contentSecondary") })
	rule("TextBox.facet-text", { PlaceholderColor3 = c("contentSecondary") })
	rule(".facet-flash", { BackgroundColor3 = c("accent") })
	rule(".facet-accent-text", { TextColor3 = c("accent") })
	rule(".facet-strong", { TextColor3 = c("contentStrong") })
	for _, role in
		{
			"surface",
			"panel",
			"control",
			"field",
			"button",
			"badge",
			"track",
			"skeleton",
			"avatar",
			"menu",
			"tab",
			"sheet",
		}
	do
		local paletteRole = if role == "surface"
			then "surface"
			elseif role == "panel" or role == "menu" or role == "sheet" then "surfaceStrong"
			else "control"
		rule(".facet-" .. role, { BackgroundColor3 = c(paletteRole), BackgroundTransparency = 0, BorderSizePixel = 0 })
		local radius = if role == "panel"
				or role == "sheet"
				or role == "menu"
			then package.metrics.radii.panel
			else package.metrics.radii.control
		rule(".facet-" .. role .. "::UICorner", { CornerRadius = types.UDim.new(0, radius) })
	end
	rule(".facet-button", {
		TextColor3 = c("content"),
		FontFace = f(package.metrics.typography.control.font),
		TextSize = package.metrics.typography.control.size,
	})
	for _, role in themes.TYPE_ROLES do
		local typography = package.metrics.typography[role] or neutral.metrics.typography[role]
		rule(".facet-button.facet-type-" .. role, { FontFace = f(typography.font), TextSize = typography.size })
	end
	for _, role in
		{ "toggle", "toggle-indicator", "slider-rail", "slider-track", "chip", "shortcut-hint", "text-input" }
	do
		rule(".facet-" .. role, { BackgroundColor3 = c("control"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	end
	rule(".facet-chip::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.pill) })
	for _, role in { "toggle-mark", "slider-fill", "slider-thumb", "selection-indicator" } do
		local ink = if role == "slider-fill" or role == "selection-indicator" then "selection" else "accent"
		rule(".facet-" .. role, { BackgroundColor3 = c(ink), BackgroundTransparency = 0, BorderSizePixel = 0 })
	end
	local skinSlots: { [string]: string } = {
		button = "control",
		field = "field",
		badge = "badge",
		panel = "panel",
		["control.facet-skinned"] = "control",
	}
	for role, slot in skinSlots do
		local chrome = package.chrome
		local recipe = if chrome then chrome[slot] else nil
		local inset: ThemeTypes.Insets = if recipe then recipe.contentInsets or {} else {}
		local regular = package.metrics.controlSizes.regular
		local horizontal = if role == "button"
			then if regular then regular.paddingX else 12
			elseif role == "badge" then 8
			elseif role == "panel" then package.metrics.space.m
			else 0
		local vertical = if role == "badge" then 3 elseif role == "panel" then package.metrics.space.m else 0
		local function side(face: number, carve: number?): UDim
			return types.UDim.new(
				0,
				if role == "badge" or role == "panel" then math.max(face, carve or 0) else face + (carve or 0)
			)
		end
		rule(".facet-" .. role .. "::UIPadding", {
			PaddingLeft = side(horizontal, inset.left),
			PaddingRight = side(horizontal, inset.right),
			PaddingTop = side(vertical, inset.top),
			PaddingBottom = side(vertical, inset.bottom),
		})
	end
	local chrome: { [string]: ThemeTypes.SkinLayer } = package.chrome or {}
	local buttonInsets: ThemeTypes.Insets = if chrome.control then chrome.control.contentInsets or {} else {}

	rule(".facet-sheet >> .facet-card-body, .facet-panel >> .facet-card-body", { BackgroundColor3 = c("control") })
	rule(".facet-sheet >> .facet-card-text, .facet-panel >> .facet-card-text", { BackgroundColor3 = c("control") })
	rule(".facet-card-text >> .facet-card-text", { BackgroundColor3 = c("surfaceStrong") })
	rule(
		".facet-sheet >> .facet-card-text >> .facet-card-text, .facet-panel >> .facet-card-text >> .facet-card-text",
		{ BackgroundColor3 = c("control") }
	)
	rule(".facet-card-text >> .facet-card-body, .facet-card-text >> .facet-card-inflow", { BackgroundTransparency = 1 })
	rule(".facet-card-text::UIPadding", {
		PaddingBottom = types.UDim.new(0, package.metrics.space.s),
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
	})

	rule(".facet-panel.facet-card-body::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})

	for _, pair in
		{ { "tablehead", "tableHeader" }, { "tablerow", "tableRow" }, { "tablerow-alternate", "tableRowAlternate" } }
	do
		rule(".facet-" .. pair[1], { BackgroundColor3 = c(pair[2]), BackgroundTransparency = 0, BorderSizePixel = 0 })
	end
	for _, band in { "tablehead", "tablerow" } do
		rule(".facet-" .. band .. "::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.control) })
	end
	for _, row in { "tablerow", "row-action" } do
		rule(".facet-" .. row .. "::UIStroke", {
			Color = c("surface"),
			Thickness = 1,
			Transparency = 0,
			BorderStrokePosition = types.Enum.BorderStrokePosition.Inner,
		})
	end
	rule(".facet-tableheading", { BackgroundTransparency = 1 })
	local function rungMetric(rung: string, field: string): number
		local authored = (package.metrics.controlSizes or {})[rung]
		if authored and type(authored[field]) == "number" then
			return authored[field]
		end
		local fallback = neutral.metrics.controlSizes[rung]
		if fallback then
			return fallback[field]
		end
		return math.max(0, 2 * rungMetric("compact", field) - rungMetric("regular", field))
	end
	local pill = math.floor(rungMetric("regular", "height") / 2 + 0.5)
	rule(".facet-button.facet-chip::UIPadding", {
		PaddingLeft = types.UDim.new(0, pill + (buttonInsets.left or 0)),
		PaddingRight = types.UDim.new(0, pill + (buttonInsets.right or 0)),
	})
	for _, rung in { "xsmall", "compact", "regular", "large" } do
		local paddingX = rungMetric(rung, "paddingX")
		rule(".facet-button.facet-size-" .. rung .. "::UIPadding", {
			PaddingLeft = types.UDim.new(0, paddingX + (buttonInsets.left or 0)),
			PaddingRight = types.UDim.new(0, paddingX + (buttonInsets.right or 0)),
		})
	end
	rule(".facet-button-tight::UIPadding", {
		PaddingLeft = types.UDim.new(0, buttonInsets.left or 0),
		PaddingRight = types.UDim.new(0, buttonInsets.right or 0),
	})
	local cellLeft, cellRight = 12 + (buttonInsets.left or 0), 12 + (buttonInsets.right or 0)
	for _, cell in { "tablevalue", "tableheading" } do
		rule(".facet-" .. cell .. "::UIPadding", {
			PaddingLeft = types.UDim.new(0, cellLeft),
			PaddingRight = types.UDim.new(0, cellRight),
		})
	end
	rule(".facet-tablecellinset", {
		Position = types.UDim2.fromOffset(cellLeft, 0),
		Size = types.UDim2.new(1, -(cellLeft + cellRight), 1, 0),
	})
	rule(".facet-button-glyph::UIPadding", {
		PaddingLeft = types.UDim.new(0, buttonInsets.left or 0),
		PaddingRight = types.UDim.new(0, buttonInsets.right or 0),
	})
	rule(".facet-button-glyph.facet-appearance-utility::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	rule(".facet-disclosure::UIPadding", { PaddingRight = types.UDim.new(0, 32 + (buttonInsets.right or 0)) })
	rule(".facet-menu-mark::UIPadding", {
		PaddingRight = types.UDim.new(
			0,
			8 + rungMetric("regular", "paddingX") + rungMetric("regular", "iconSize") + (buttonInsets.right or 0)
		),
	})
	rule(".facet-button-described::UIPadding", {
		PaddingTop = types.UDim.new(0, 10 + (buttonInsets.top or 0)),
		PaddingBottom = types.UDim.new(0, 10 + (buttonInsets.bottom or 0)),
	})
	rule(".facet-toggle-row::UIPadding", { PaddingLeft = types.UDim.new(0, 0), PaddingRight = types.UDim.new(0, 0) })
	rule(".facet-toggle-settings::UIPadding", {
		PaddingLeft = types.UDim.new(0, 12 + (buttonInsets.left or 0)),
		PaddingRight = types.UDim.new(0, 12 + (buttonInsets.right or 0)),
	})
	rule(".facet-slider-settings::UIPadding", {
		PaddingLeft = types.UDim.new(0, 12 + (buttonInsets.left or 0)),
		PaddingRight = types.UDim.new(0, 12 + (buttonInsets.right or 0)),
	})
	local space: { [string]: number } = package.metrics.space or neutral.metrics.space
	local rowGap = space.xs or neutral.metrics.space.xs
	rule(".facet-calendar-choice::UIPadding", {
		PaddingLeft = types.UDim.new(0, rowGap),
		PaddingRight = types.UDim.new(0, rowGap),
	})
	for _, rung in { "", "xsmall", "compact", "regular", "large" } do
		local step = if rung == "" then "regular" else rung
		local paddingX = rungMetric(step, "paddingX")
		local paddingY = math.max(0, (rungMetric(step, "height") - rungMetric(step, "iconSize") - rowGap) // 2)
		rule(".facet-list-row" .. (if rung == "" then "" else ".facet-size-" .. rung) .. "::UIPadding", {
			PaddingLeft = types.UDim.new(0, paddingX + (buttonInsets.left or 0)),
			PaddingRight = types.UDim.new(0, paddingX + (buttonInsets.right or 0)),
			PaddingTop = types.UDim.new(0, math.max(paddingY, buttonInsets.top or 0)),
			PaddingBottom = types.UDim.new(0, math.max(paddingY, buttonInsets.bottom or 0)),
		})
	end
	rule(".facet-menu-dense::UIPadding", { PaddingTop = types.UDim.new(0, 0), PaddingBottom = types.UDim.new(0, 0) })
	rule(".facet-busy::UIPadding", { PaddingRight = types.UDim.new(0, 32 + (buttonInsets.right or 0)) })
	rule(".facet-shape-circle::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	rule(".facet-button-media::UIPadding", {
		PaddingLeft = types.UDim.new(0, buttonInsets.left or 0),
		PaddingRight = types.UDim.new(0, buttonInsets.right or 0),
		PaddingTop = types.UDim.new(0, buttonInsets.top or 0),
		PaddingBottom = types.UDim.new(0, 10 + (buttonInsets.bottom or 0)),
	})
	rule(".facet-button-media-body::UIPadding", {
		PaddingLeft = types.UDim.new(0, 12),
		PaddingRight = types.UDim.new(0, 12),
	})
	rule(".facet-button-captioned", { TextTransparency = 1 })
	rule(".facet-badge-captioned", { TextTransparency = 1 })
	rule(".facet-badge-caption", { TextTransparency = 0 })
	rule(".facet-button-caption", {
		TextTransparency = 0,
		TextColor3 = c("content"),
		FontFace = f(package.metrics.typography.control.font),
		TextSize = package.metrics.typography.control.size,
	})
	rule(".facet-accent >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-disabled >> .facet-button-caption", { TextTransparency = extra.disabledContentOpacity })
	rule(".facet-disabled >> .facet-text", { TextTransparency = extra.disabledContentOpacity })
	rule(".facet-skin-caption > Frame > Frame > .facet-button-caption", { TextTransparency = 1 })
	rule(".facet-skin-caption-text", {
		TextTransparency = 0,
		TextColor3 = c("content"),
		BackgroundTransparency = 1,
		FontFace = f(package.metrics.typography.control.font),
		TextSize = package.metrics.typography.control.size,
	})
	rule(".facet-button:Hover", { BackgroundColor3 = c("controlHover") })
	rule(".facet-button:Press", { BackgroundColor3 = c("controlPressed") })
	rule(".facet-role-destructive", { BackgroundColor3 = c("danger"), TextColor3 = c("onDanger") })
	rule(".facet-role-destructive:Hover", { BackgroundColor3 = c("danger") })
	rule(".facet-role-destructive:Press", { BackgroundColor3 = c("danger") })
	rule(".facet-role-destructive >> .facet-button-caption", { TextColor3 = c("onDanger") })
	rule(".facet-role-cancel", { TextColor3 = c("contentSecondary") })
	rule(".facet-role-cancel >> .facet-button-caption", { TextColor3 = c("contentSecondary") })
	rule(".facet-role-onIndicator >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-role-destructive >> .facet-text", { TextColor3 = c("onDanger") })
	local onSelected = c("onSelected") or c("content")
	rule(".facet-selected", { BackgroundColor3 = c("controlSelected"), TextColor3 = onSelected })
	rule(".facet-selected >> .facet-text", { TextColor3 = onSelected })
	rule(
		".facet-selected >> .facet-card-part, .facet-selected >> .facet-card-text",
		{ BackgroundColor3 = c("controlSelected") }
	)
	rule(".facet-disabled", { TextTransparency = extra.disabledContentOpacity })
	rule(".facet-disabled >> .facet-icon", { ImageTransparency = extra.disabledContentOpacity })

	rule(".facet-drag-held", { TextTransparency = 1 })
	rule(".facet-drag-held >> .facet-text", { TextTransparency = 1 })
	rule(".facet-drag-held >> .facet-icon", { ImageTransparency = 1 })
	rule(".facet-accent", { BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") })
	rule(".facet-fill", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-track >> .facet-fill::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.control) })
	rule(".facet-level-segment", { BackgroundColor3 = c("control"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-level-on", { BackgroundColor3 = c("accent") })
	rule(".facet-progress-ring-track", { Color3 = c("control") })
	rule(".facet-path", { Color3 = c("content") })
	rule(".facet-path-content", { Color3 = c("content") })
	rule(".facet-path-secondary", { Color3 = c("contentSecondary") })
	rule(".facet-path-accent", { Color3 = c("accent") })
	rule(".facet-accent >> .facet-button-glyph >> .facet-path", { Color3 = c("onAccent") })
	rule(".facet-selected >> .facet-button-glyph >> .facet-path", { Color3 = onSelected })
	rule(".facet-role-destructive >> .facet-button-glyph >> .facet-path", { Color3 = c("onDanger") })
	rule(".facet-role-cancel >> .facet-button-glyph >> .facet-path", { Color3 = c("contentSecondary") })
	rule(".facet-role-onIndicator >> .facet-button-glyph >> .facet-path", { Color3 = c("onAccent") })
	rule(".facet-disabled >> .facet-button-glyph >> .facet-path", { Color3 = c("contentSecondary") })
	rule(".facet-progress-ring-fill", { Color3 = c("accent") })
	rule(".facet-progress-gauge-needle", { Color3 = c("content") })
	rule(".facet-progress-gauge-hub", { BackgroundColor3 = c("content"), BackgroundTransparency = 0 })
	rule(".facet-icon", { ImageColor3 = c("content"), BackgroundTransparency = 1 })
	rule(".facet-role-destructive >> .facet-icon", { ImageColor3 = c("onDanger") })
	rule(".facet-selected >> .facet-icon", { ImageColor3 = onSelected })
	rule(
		".facet-divider",
		{ BackgroundColor3 = c("hairline"), BackgroundTransparency = extra.hairlineOpacity, BorderSizePixel = 0 }
	)
	rule(".facet-divider-strong", {
		BackgroundTransparency = extra.strongHairlineOpacity
			or math.max(0, 1 - (1 - (extra.hairlineOpacity or 0.92)) * 3),
	})
	rule(".facet-pane", { BackgroundColor3 = c("surfaceStrong"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-scrim", {
		BackgroundColor3 = color(types, extra.scrim) or types.Color3.new(0, 0, 0),
		BackgroundTransparency = 1 - (extra.scrimOpacity or 0.45),
		BorderSizePixel = 0,
	})
	rule(".facet-scrim.facet-radial-scrim", {
		BackgroundColor3 = types.Color3.new(0, 0, 0),
		BackgroundTransparency = 1 - math.max(extra.scrimOpacity or 0.45, 0.8),
	})
	local statusRoles: { [string]: string } = {
		neutral = "contentSecondary",
		info = "accent",
		success = "success",
		warning = "warning",
		error = "danger",
		accent = "accent",
		voice = "voice",
		contrast = "contentStrong",
	}
	local function partnerOf(status: string): string
		return if status == "neutral"
			then "surface"
			elseif status == "error" then "onDanger"
			elseif status == "info" or status == "accent" then "onAccent"
			elseif status == "warning" or status == "voice" then "onWarning"
			elseif status == "contrast" then "surface"
			else "onSuccess"
	end
	for status, role in statusRoles do
		local partner = partnerOf(status)
		rule(".facet-status-" .. status, { BackgroundColor3 = c(role), TextColor3 = c(partner) })
		rule(".facet-status-" .. status .. " > .facet-status-ring", { Color = c(role) })
		rule(".facet-icon-" .. status, { ImageColor3 = c(role), BackgroundTransparency = 1 })
		rule(".facet-status-" .. status .. " > .facet-text", { TextColor3 = c(partner) })
		rule(".facet-status-" .. status .. " > .facet-icon", { ImageColor3 = c(partner) })
	end
	rule(".facet-status-surface", { BackgroundTransparency = 0 })
	rule(".facet-status-surface >> .facet-track", { BackgroundTransparency = 0.7 })
	for status in statusRoles do
		local partner = c(partnerOf(status))
		local surface = ".facet-status-surface.facet-status-" .. status
		rule(`{surface} >> .facet-text, {surface} >> .facet-icon`, { TextColor3 = partner, ImageColor3 = partner })
		rule(`{surface} >> .facet-fill, {surface} >> .facet-track`, { BackgroundColor3 = partner })
	end
	rule(".facet-badge-on-media::UIStroke", { Thickness = 1, Transparency = 0.5 })
	for status in statusRoles do
		rule(".facet-badge-on-media.facet-status-" .. status .. "::UIStroke", { Color = c(partnerOf(status)) })
	end
	rule(".facet-status-hollow", { BackgroundTransparency = 1 })
	rule(".facet-badge-utility", { BackgroundTransparency = 1, TextColor3 = c("contentSecondary") })
	rule(".facet-badge-utility > .facet-text", { TextColor3 = c("contentSecondary") })
	rule(".facet-badge-utility > .facet-icon", { ImageColor3 = c("contentSecondary") })
	rule(".facet-badge-status", { BackgroundColor3 = c("control"), TextColor3 = c("content") })
	rule(".facet-badge-status > .facet-text", { TextColor3 = c("content") })
	rule(".facet-badge-status > .facet-icon", { ImageColor3 = c("content") })
	rule(".facet-badge-status::UIPadding", { PaddingLeft = types.UDim.new(0, 20) })
	rule(".facet-cutout", { Color = c("surface") })
	local gradients: { [string]: ThemeTypes.Gradient } = extra.chromeGradient or {}
	for role, gradient in gradients do
		local stops: { ColorSequenceKeypoint }, alpha: { NumberSequenceKeypoint } = {}, {}
		for _, stop in gradient.stops do
			table.insert(stops, types.ColorSequenceKeypoint.new(stop.t, types.Color3.new(stop.r, stop.g, stop.b)))
		end
		local alphaStops: { { t: number, v: number } } = gradient.alpha or {}
		for _, stop in alphaStops do
			table.insert(alpha, types.NumberSequenceKeypoint.new(stop.t, stop.v))
		end
		if #stops >= 2 then
			local properties: ThemeTypes.RuleProperties =
				{ Color = types.ColorSequence.new(stops), Rotation = gradient.rotation or 90 }
			if #alpha >= 2 then
				properties.Transparency = types.NumberSequence.new(alpha)
			end
			rule(".facet-" .. role .. "::UIGradient", properties)
		end
	end

	rule(".facet-shortcut-hint", {
		BackgroundColor3 = c("surfaceStrong"),
		TextColor3 = c("contentStrong"),
		TextSize = package.metrics.typography.caption.size,
	})
	rule(".facet-shortcut-glyph", { ImageColor3 = c("contentStrong") })
	rule(
		".facet-shortcut-hint::UICorner",
		{ CornerRadius = types.UDim.new(0, math.min(6, package.metrics.radii.control)) }
	)
	local families: { [string]: { [string]: number } } = package.metrics.controls or {}
	local hintFamily: { [string]: number } = families.shortcutHint or {}
	local capStroke = hintFamily.capStroke or package.metrics.strokes.hairline or 1
	if capStroke > 0 then
		rule(".facet-shortcut-hint::UIStroke", {
			Color = c("hairline"),
			Transparency = extra.hairlineOpacity or 0.92,
			Thickness = capStroke,
			ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
		})
	end
	rule(".facet-shortcut-hint::UIPadding", {
		PaddingLeft = types.UDim.new(0, 8),
		PaddingRight = types.UDim.new(0, 8),
	})
	rule(".facet-shortcut-hint.facet-shortcut-hint-bare::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
	})
	rule(".facet-shortcut-hint.facet-shortcut-hint-bare::UIStroke", { Transparency = 1 })
	rule(".facet-toggle-row", { BackgroundTransparency = 1 })
	rule(".facet-toggle-row:Hover", { BackgroundTransparency = 1 })
	rule(".facet-toggle-row:Press", { BackgroundTransparency = 1 })
	rule(".facet-toggle-row.facet-selected", { TextColor3 = c("content") })
	rule(".facet-toggle-row.facet-selected >> .facet-text", { TextColor3 = c("content") })
	rule(".facet-toggle-row.facet-selected >> .facet-icon", { ImageColor3 = c("content") })
	rule(".facet-toggle-plain", { BackgroundTransparency = 1 })
	rule(".facet-toggle-indicator", { BackgroundColor3 = c("control"), BackgroundTransparency = 0 })
	rule(".facet-toggle-on", { BackgroundColor3 = c("selection") })
	local knob, offTrack, loudKnob =
		resolved("onSelection") :: Color3, resolved("control") :: Color3, resolved("content") :: Color3
	local offKnob = if contrast(knob, offTrack) >= 3
			or contrast(knob, offTrack) >= contrast(loudKnob, offTrack)
		then knob
		else loudKnob
	rule(".facet-toggle-switch >> .facet-toggle-mark", { BackgroundColor3 = offKnob })
	rule(".facet-toggle-checkbox >> .facet-toggle-mark", { BackgroundColor3 = knob })
	rule(".facet-toggle-on >> .facet-toggle-mark", { BackgroundColor3 = knob })
	rule(".facet-toggle-check", { ImageColor3 = c("onSelection") })
	rule(".facet-toggle-checkbox::UIStroke", { Color = c("contentSecondary"), Thickness = 1.5, Transparency = 0.2 })
	rule(".facet-tooltip", { BackgroundColor3 = c("surfaceStrong"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-tooltip::UICorner", { CornerRadius = types.UDim.new(0, math.min(6, package.metrics.radii.control)) })
	rule(".facet-tooltip::UIStroke", { Color = c("hairline"), Transparency = 0.4, Thickness = 1 })
	rule(".facet-appearance-utility", { BackgroundTransparency = 1 })
	rule(".facet-appearance-utility:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-appearance-utility:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(
		".facet-appearance-soft",
		{ BackgroundColor3 = c("accent"), BackgroundTransparency = 0.8, TextColor3 = c("accent") }
	)
	rule(".facet-appearance-soft:Hover", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0.7 })
	rule(".facet-appearance-soft:Press", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0.6 })
	rule(".facet-appearance-soft >> .facet-button-caption", { TextColor3 = c("accent") })
	rule(".facet-appearance-soft >> .facet-icon", { ImageColor3 = c("accent") })
	local linkInk = if contrast(assert(resolved("accent")), assert(resolved("surface"))) >= 4.5
		then c("accent")
		else c("content")
	rule(".facet-appearance-link", { BackgroundTransparency = 1, TextColor3 = linkInk })
	rule(".facet-appearance-link:Hover", { BackgroundTransparency = 1, TextColor3 = linkInk })
	rule(".facet-appearance-link:Press", { BackgroundTransparency = 1, TextTransparency = 0.3 })
	rule(".facet-appearance-link >> .facet-button-caption", { TextColor3 = linkInk })
	rule(".facet-appearance-link >> .facet-icon", { ImageColor3 = linkInk })
	rule(".facet-appearance-link:Press >> .facet-button-caption", { TextTransparency = 0.3 })
	rule(".facet-appearance-link:Press >> .facet-text", { TextTransparency = 0.3 })
	rule(".facet-appearance-link:Press >> .facet-icon", { ImageTransparency = 0.3 })
	rule(
		".facet-appearance-link::UIPadding",
		{ PaddingLeft = types.UDim.new(0, 0), PaddingRight = types.UDim.new(0, 0) }
	)
	local inverse, onInverse = source("inverseSurface"), source("onInverse")
	rule(
		".facet-appearance-inverse",
		{ BackgroundColor3 = c("inverseSurface"), BackgroundTransparency = 0, TextColor3 = c("onInverse") }
	)
	if inverse and onInverse then
		local function toward(amount: number): Color3
			return types.Color3.new(
				inverse.r + (onInverse.r - inverse.r) * amount,
				inverse.g + (onInverse.g - inverse.g) * amount,
				inverse.b + (onInverse.b - inverse.b) * amount
			)
		end
		rule(".facet-appearance-inverse:Hover", { BackgroundColor3 = toward(0.12), TextColor3 = c("onInverse") })
		rule(".facet-appearance-inverse:Press", { BackgroundColor3 = toward(0.2), TextColor3 = c("onInverse") })
	end
	rule(".facet-appearance-inverse >> .facet-button-caption", { TextColor3 = c("onInverse") })
	rule(".facet-appearance-inverse >> .facet-text", { TextColor3 = c("onInverse") })
	rule(".facet-appearance-inverse >> .facet-icon", { ImageColor3 = c("onInverse") })
	local utilityStroke = package.metrics.strokes.utility
	if type(utilityStroke) == "number" and utilityStroke > 0 then
		rule(".facet-appearance-utility::UIStroke", {
			Color = c("hairline"),
			Transparency = extra.hairlineOpacity,
			Thickness = utilityStroke,
			ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
		})
	end
	rule(".facet-button.facet-radial-label::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	rule(".facet-grabber", { BackgroundColor3 = c("contentSecondary"), BackgroundTransparency = 0.5 })
	rule(".facet-menu-item", { BackgroundTransparency = 1 })
	rule(".facet-menu-item:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-menu-item:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(".facet-menu-destructive", { BackgroundTransparency = 1, TextColor3 = c("danger") })
	rule(".facet-menu-destructive:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-menu-destructive:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(".facet-menu-destructive >> .facet-button-caption", { TextColor3 = c("danger") })
	rule(".facet-menu-destructive >> .facet-icon", { ImageColor3 = c("danger") })
	rule(".facet-menu::UIStroke", {
		Color = c("hairline"),
		Transparency = 0.3,
		Thickness = 1,
		ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
	})
	rule(".facet-menu::UIShadow", {
		BlurRadius = types.UDim.new(0, 14),
		Transparency = 0.35,
		Offset = types.UDim2.fromOffset(0, 3),
	})
	rule(".facet-menu-group::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.panel) })
	rule(
		".facet-menu-hairline",
		{ BackgroundColor3 = c("hairline"), BackgroundTransparency = extra.hairlineOpacity, BorderSizePixel = 0 }
	)
	for _, state in { "", ":Hover", ":Press" } do
		rule(".facet-menu-item.facet-selected" .. state, {
			BackgroundTransparency = 0,
			BackgroundColor3 = c("accent"),
			TextColor3 = c("onAccent"),
		})
	end
	rule(".facet-menu-item.facet-selected >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-menu-item.facet-selected >> .facet-text", { TextColor3 = c("onAccent") })
	rule(".facet-menu-item.facet-selected >> .facet-icon", { ImageColor3 = c("onAccent") })
	rule(".facet-radial-sector", { Color3 = c("surfaceStrong") })
	rule(".facet-radial-sector.facet-radial-candidate", { Color3 = c("controlSelected") })
	rule(".facet-radial-item::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	rule(".facet-button.facet-radial-row", { BackgroundTransparency = 0 })
	rule(".facet-page-indicator", { BackgroundTransparency = 1 })
	rule(".facet-page-indicator:Hover", { BackgroundTransparency = 1 })
	rule(".facet-page-indicator:Press", { BackgroundTransparency = 1 })
	rule(".facet-page-indicator.facet-selected", { BackgroundTransparency = 1 })
	rule(".facet-page-dot", { BackgroundColor3 = c("contentSecondary"), BackgroundTransparency = 0 })
	rule(".facet-page-indicator:Hover >> .facet-page-dot", { BackgroundColor3 = c("content") })
	rule(".facet-page-indicator.facet-selected >> .facet-page-dot", {
		BackgroundColor3 = c("accent"),
		BackgroundTransparency = 0,
	})
	rule(".facet-floating::UIStroke", { Color = c("hairline"), Transparency = 0.3, Thickness = 1 })
	rule(".facet-tail", { BackgroundColor3 = c("surfaceStrong"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	local outlineInk = color(types, source("hairline")) :: Color3
	local outlineFill = color(types, source("surfaceStrong")) :: Color3
	rule(".facet-outlined::UIStroke", { Transparency = 1 })
	rule(".facet-outline", { Color3 = outlineInk:Lerp(outlineFill, 0.3), Thickness = 1 })
	rule(".facet-outline-tooltip", { Color3 = outlineInk:Lerp(outlineFill, 0.4) })
	rule(".facet-step-circle::UIStroke", { Color = c("contentSecondary"), Thickness = 1 })
	rule(".facet-invalid::UIStroke", { Color = c("danger"), Thickness = 1 })
	rule(".facet-date-time-picker", { BackgroundTransparency = 1 })
	rule(".facet-radio-mark::UIStroke", { Color = c("contentSecondary"), Thickness = 1.5 })
	rule(".facet-segmented-stroke", { BackgroundTransparency = 1 })
	rule(".facet-segmented-stroke::UIStroke", { Color = c("hairline"), Thickness = 1 })
	rule(".facet-segmented-utility", { BackgroundTransparency = 1 })
	rule(".facet-card-option::UIStroke", { Color = c("hairline"), Thickness = 1 })
	rule(".facet-color-picker", { BackgroundTransparency = 1 })
	rule(".facet-color-swatch::UIStroke", { Color = c("hairline"), Transparency = 0, Thickness = 1 })
	rule(".facet-color-swatch >> UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.control) })
	rule(".facet-color-cell::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	for _, member in { ".facet-avatar", ".facet-button" } do
		rule(".facet-avatar-stack > " .. member .. "::UIStroke", {
			Color = c("surface"),
			Thickness = 2,
			ApplyStrokeMode = types.Enum.ApplyStrokeMode.Border,
			BorderStrokePosition = types.Enum.BorderStrokePosition.Outer,
		})
	end
	for role, ink in AVATAR_BACKGROUNDS do
		local selector = ".facet-avatar-background-" .. role
		rule(selector, { BackgroundColor3 = c(role), BackgroundTransparency = 0, TextColor3 = c(ink) })
		rule(selector .. " > .facet-text", { TextColor3 = c(ink) })
		rule(selector .. " > .facet-icon", { ImageColor3 = c(ink) })
	end
	local focus = if package.chrome then package.chrome.focus else nil
	local focusColor = if focus then focus.color else nil
	rule(".facet-focus-ring", {
		BackgroundColor3 = if type(focusColor) == "table"
			then color(types, focusColor)
			elseif type(focusColor) == "string" then c(
				string.lower(string.sub(focusColor, 2, 2)) .. string.sub(focusColor, 3)
			) or c("accent")
			else c("accent"),
	})
	rule(".facet-focus-ring::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.control) })
	rule(".facet-drop-line", { BackgroundColor3 = c("accent") })
	rule(".facet-drop-accepted", { Color = c("accent") })
	rule(".facet-drop-rejected", { Color = c("danger") })
	rule(".facet-avatar-ring", { Color = c("accent"), Transparency = 0 })
	rule(".facet-avatar-hover", { Color = c("accent") })
	rule(".facet-avatar-ring-gap", { Color = c("surface"), Transparency = 0 })
	rule(".facet-quiet-destructive", { TextColor3 = c("danger") })
	rule(".facet-quiet-destructive:Hover", { TextColor3 = c("danger") })
	rule(".facet-quiet-destructive:Press", { TextColor3 = c("danger") })
	rule(".facet-quiet-destructive >> .facet-button-caption", { TextColor3 = c("danger") })
	rule(".facet-quiet-destructive >> .facet-icon", { ImageColor3 = c("danger") })

	local track, quiet, loud =
		resolved("control") :: Color3, resolved("contentSecondary") :: Color3, resolved("content") :: Color3
	local segmentInk = if contrast(quiet, track) >= 4.5 or contrast(quiet, track) >= contrast(loud, track)
		then quiet
		else loud
	rule(".facet-tab-item.facet-button-tight::UIPadding", {
		PaddingLeft = types.UDim.new(0, rowGap + (buttonInsets.left or 0)),
		PaddingRight = types.UDim.new(0, rowGap + (buttonInsets.right or 0)),
	})
	rule(".facet-tab-item", { BackgroundTransparency = 1, TextColor3 = c("contentSecondary") })
	rule(".facet-tab-item >> .facet-button-caption", { TextColor3 = c("contentSecondary") })
	rule(".facet-tab-item.facet-skinned", { TextColor3 = segmentInk })
	rule(".facet-tab-item.facet-skinned >> .facet-button-caption", { TextColor3 = segmentInk })
	rule(".facet-tab-item:Hover", { BackgroundTransparency = 1, TextColor3 = c("content") })
	rule(".facet-tab-item:Hover >> .facet-button-caption", { TextColor3 = c("content") })
	rule(".facet-tab-item:Press", { BackgroundTransparency = 1, TextColor3 = c("content") })
	rule(".facet-tab-item:Press >> .facet-button-caption", { TextColor3 = c("content") })
	rule(".facet-tab-current", { TextColor3 = c("content") })
	rule(".facet-tab-current >> .facet-button-caption", { TextColor3 = c("content") })
	rule(".facet-tab-item.facet-selected", { BackgroundTransparency = 0, TextColor3 = onSelected })
	rule(".facet-tab-item.facet-selected >> .facet-button-caption", { TextColor3 = onSelected })
	rule(
		".facet-tab-filled",
		{ BackgroundTransparency = 0, BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") }
	)
	rule(".facet-tab-filled >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-tab-filled >> .facet-icon", { ImageColor3 = c("onAccent") })
	rule(".facet-tab-filled >> .facet-tab-glyph >> .facet-path", { Color3 = c("onAccent") })
	rule(".facet-stepper-track", { BackgroundColor3 = c("control"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(".facet-stepper-track::UICorner", { CornerRadius = types.UDim.new(0, package.metrics.radii.control) })
	rule(".facet-skinned > #Content > .facet-stepper-track", { BackgroundTransparency = 1 })
	do
		local recipe = if package.chrome then package.chrome.stepperPlate else nil
		local inset: ThemeTypes.Insets = if recipe then recipe.contentInsets or {} else {}
		rule(".facet-skinned >> .facet-stepper-inset", {
			PaddingLeft = types.UDim.new(0, math.max(12, inset.left or 0)),
		})
	end
	rule(".facet-stepper-button", { BackgroundTransparency = 1 })
	rule(".facet-stepper-button:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-stepper-button:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(".facet-choice", { BackgroundTransparency = 1, TextXAlignment = types.Enum.TextXAlignment.Left })
	rule(".facet-choice:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-choice:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(
		".facet-choice-current",
		{ BackgroundTransparency = 0.82, BackgroundColor3 = c("accent"), TextColor3 = c("accent") }
	)
	rule(".facet-choice-current:Hover", { BackgroundTransparency = 0.72, BackgroundColor3 = c("accent") })
	rule(".facet-choice-current:Press", { BackgroundTransparency = 0.62, BackgroundColor3 = c("accent") })
	rule(".facet-choice-current >> .facet-button-caption", { TextColor3 = c("accent") })
	rule(".facet-choice-current >> .facet-icon", { ImageColor3 = c("accent") })
	rule(".facet-segmented", { BackgroundColor3 = c("control"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	local trackRadius = if package.metrics.radii.control > 0 then package.metrics.radii.control + 2 else 0
	rule(".facet-segmented::UICorner", { CornerRadius = types.UDim.new(0, trackRadius) })

	rule(".facet-tab-plate", { BackgroundColor3 = c("surfaceStrong") })
	local tabRadius = package.metrics.radii.tab or package.metrics.radii.control
	rule(".facet-top-tabs > .facet-tab-plate::UICorner", {
		CornerRadius = types.UDim.new(0, if tabRadius > 0 then tabRadius + 2 else 0),
	})
	rule(".facet-top-tabs > #Tabs >> .facet-tab-item::UICorner", { CornerRadius = types.UDim.new(0, tabRadius) })
	rule(".facet-tab-plate::UIStroke", {
		Color = c("hairline"),
		Transparency = extra.hairlineOpacity,
		Thickness = package.metrics.strokes.hairline or 1,
	})
	rule(".facet-segmented::UIPadding", {
		PaddingLeft = types.UDim.new(0, SEGMENT_INSET),
		PaddingRight = types.UDim.new(0, SEGMENT_INSET),
		PaddingTop = types.UDim.new(0, SEGMENT_INSET),
		PaddingBottom = types.UDim.new(0, SEGMENT_INSET),
	})
	rule(".facet-segment", { BackgroundTransparency = 1, TextColor3 = segmentInk })
	rule(".facet-segment::UICorner", { CornerRadius = types.UDim.new(0, math.max(0, trackRadius - SEGMENT_INSET)) })
	rule(".facet-segmented-pill >> .facet-segment::UICorner", { CornerRadius = types.UDim.new(1, 0) })
	rule(".facet-segmented-square >> .facet-segment::UICorner", { CornerRadius = types.UDim.new(0, 0) })
	rule(".facet-segment-fill", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0, BorderSizePixel = 0 })
	rule(
		".facet-segment-fill::UICorner",
		{ CornerRadius = types.UDim.new(0, math.max(0, trackRadius - SEGMENT_INSET)) }
	)
	rule(".facet-segmented-pill >> .facet-segment-fill::UICorner", { CornerRadius = types.UDim.new(1, 0) })
	rule(".facet-segmented-square >> .facet-segment-fill::UICorner", { CornerRadius = types.UDim.new(0, 0) })
	rule(".facet-segment >> .facet-button-caption", { TextColor3 = segmentInk })
	rule(
		".facet-segment:Hover",
		{ BackgroundTransparency = 0, BackgroundColor3 = c("controlHover"), TextColor3 = c("content") }
	)
	rule(
		".facet-segment:Press",
		{ BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed"), TextColor3 = c("content") }
	)
	rule(
		".facet-segment-current",
		{ BackgroundTransparency = 0, BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") }
	)
	rule(".facet-segment-current:Hover", { BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") })
	rule(".facet-segment-current:Press", { BackgroundColor3 = c("accent"), TextColor3 = c("onAccent") })
	rule(".facet-segment-current >> .facet-button-caption", { TextColor3 = c("onAccent") })
	rule(".facet-segment-current >> .facet-icon", { ImageColor3 = c("onAccent") })
	rule(".facet-menu-destructive >> .facet-text", { TextColor3 = c("danger") })
	rule(".facet-appearance-soft >> .facet-text", { TextColor3 = c("accent") })
	rule(".facet-appearance-link >> .facet-text", { TextColor3 = linkInk })
	rule(".facet-quiet-destructive >> .facet-text", { TextColor3 = c("danger") })
	rule(".facet-menu-item::UICorner", {
		CornerRadius = types.UDim.new(
			0,
			math.max(0, package.metrics.radii.panel - (package.metrics.space or neutral.metrics.space).xs)
		),
	})
	rule(".facet-menu-destructive", { TextColor3 = c("content") })
	rule(".facet-menu-destructive >> .facet-button-caption", { TextColor3 = c("content") })
	rule(".facet-menu-destructive >> .facet-text", { TextColor3 = c("content") })
	for _, state in { ":Hover", ":Press" } do
		rule(".facet-menu-destructive" .. state, { BackgroundTransparency = 0, BackgroundColor3 = c("danger") })
		rule(".facet-menu-destructive" .. state .. " >> .facet-button-caption", { TextColor3 = c("onDanger") })
		rule(".facet-menu-destructive" .. state .. " >> .facet-text", { TextColor3 = c("onDanger") })
		rule(".facet-menu-destructive" .. state .. " >> .facet-icon", { ImageColor3 = c("onDanger") })
	end
	rule(".facet-choice-current >> .facet-text", { TextColor3 = c("accent") })
	rule(".facet-tab-filled >> .facet-text", { TextColor3 = c("onAccent") })
	rule(".facet-segment-current >> .facet-text", { TextColor3 = c("onAccent") })
	rule(".facet-accent >> .facet-text", { TextColor3 = c("onAccent") })
	rule(".facet-accent >> .facet-icon", { ImageColor3 = c("onAccent") })
	local bareGlyph = " >> .facet-shortcut-hint-bare >> .facet-shortcut-glyph"
	rule(".facet-role-destructive" .. bareGlyph, { ImageColor3 = c("onDanger") })
	rule(".facet-appearance-inverse" .. bareGlyph, { ImageColor3 = c("onInverse") })
	rule(".facet-accent" .. bareGlyph, { ImageColor3 = c("onAccent") })
	local buttonFamily: { [string]: number } = families.button or {}
	local captionStroke = buttonFamily.captionStroke or 1.5
	if captionStroke > 0 then
		local halo: ThemeTypes.RuleProperties = {
			ApplyStrokeMode = types.Enum.ApplyStrokeMode.Contextual,
			Color = c("surface"),
			Thickness = captionStroke,
			Transparency = 1 - (buttonFamily.captionStrokeOpacity or 0.7),
		}
		rule("TextLabel.facet-button-outside::UIStroke", halo)
		rule(".facet-button-outside >> .facet-text::UIStroke", halo)
	end
	rule(".facet-calendar-day", { BackgroundTransparency = 1 })
	rule(".facet-calendar-day::UIPadding", {
		PaddingLeft = types.UDim.new(0, 0),
		PaddingRight = types.UDim.new(0, 0),
		PaddingTop = types.UDim.new(0, 0),
		PaddingBottom = types.UDim.new(0, 0),
	})
	local calendarInsets: ThemeTypes.Insets = if package.chrome and package.chrome.panel
		then package.chrome.panel.contentInsets or {}
		else {}
	rule(".facet-panel.facet-calendar-scroll::UIPadding", {
		PaddingLeft = types.UDim.new(0, calendarInsets.left or 0),
		PaddingRight = types.UDim.new(0, calendarInsets.right or 0),
		PaddingTop = types.UDim.new(0, calendarInsets.top or 0),
		PaddingBottom = types.UDim.new(0, calendarInsets.bottom or 0),
	})
	rule(".facet-calendar-day:Hover", { BackgroundTransparency = 0, BackgroundColor3 = c("controlHover") })
	rule(".facet-calendar-day:Press", { BackgroundTransparency = 0, BackgroundColor3 = c("controlPressed") })
	rule(".facet-calendar-band", { BackgroundColor3 = c("controlSelected"), BackgroundTransparency = 0 })
	rule(".facet-calendar-disc", { BackgroundColor3 = c("accent"), BackgroundTransparency = 0 })
	rule(".facet-calendar-end", { BackgroundColor3 = c("content") })
	rule(".facet-calendar-today::UIStroke", { Color = c("accent"), Thickness = 1 })
	rule(".facet-calendar-strike", { BackgroundColor3 = c("contentSecondary"), BackgroundTransparency = 0 })
	rule(".facet-calendar-number", { FontFace = f({ weight = "SemiBold" }) })
	rule(".facet-calendar-banded", { TextColor3 = onSelected })
	rule(".facet-calendar-dim", { TextColor3 = c("contentSecondary"), FontFace = f({ weight = "Regular" }) })
	rule(".facet-calendar-chosen", { TextColor3 = c("onAccent") })
	rule(".facet-calendar-chosen-end", { TextColor3 = c("surface") })
	rule(".facet-skinned", { BackgroundTransparency = 1 })

	for _, slot in { "control", "field", "panel", "panelTail" } do
		rule(".facet-skin-art-" .. slot, if extra.artTint then { ImageColor3 = c("artTint") } else {})
	end
	for status, role in statusRoles do
		rule(".facet-badge.facet-status-" .. status .. " > #SkinBoundary >> .facet-skin-art", { ImageColor3 = c(role) })
	end
	for _, appearance in { "status", "utility" } do
		rule(
			".facet-badge-" .. appearance .. " > #SkinBoundary >> .facet-skin-art",
			{ ImageColor3 = types.Color3.new(1, 1, 1) }
		)
	end
	local plate = chrome.control
	local selectedArt: ThemeTypes.AssetLink? = nil
	local selectedLayer = 0
	local plateLayers: { ThemeTypes.SkinLayer } = if plate == nil
		then {}
		elseif plate.kind == "layered" then plate.layers or {}
		else { plate }
	for index, layer in plateLayers do
		local link = if type(layer.asset) == "table" then (layer.asset :: ThemeTypes.AssetVariants).selected else nil
		if link ~= nil and selectedArt == nil then
			selectedArt, selectedLayer = link, index
		end
	end
	local selectedLink: { asset: string, rotation: number?, tint: ThemeTypes.RGB? }? = if type(selectedArt)
			== "string"
		then { asset = selectedArt }
		else selectedArt
	local white, black = types.Color3.new(1, 1, 1), types.Color3.new(0, 0, 0)
	local art = if selectedLink then (package.assets or {})[selectedLink.asset] else nil
	local pressedEmphasis = false
	for _, theme in package.style.themes do
		local swatch = merge(support.neutralBase(neutral, theme.colors).colors, theme.colors)
		local fill, ink = color(types, swatch.accent), color(types, swatch.onAccent)
		if art and fill and ink and contrast(ink, black) <= contrast(fill, black) then
			pressedEmphasis = true
		end
	end
	for _, entry in { { ".facet-role-destructive", "danger", "onDanger" }, { ".facet-accent", "accent", "onAccent" } } do
		local selector, fill, ink = entry[1], resolved(entry[2]) :: Color3, resolved(entry[3]) :: Color3
		local pressed = pressedEmphasis and entry[2] == "accent"
		local tinted = not pressed and contrast(ink, black) > contrast(fill, black)
		rule(selector .. " > #SkinBoundary >> .facet-skin-art", { ImageColor3 = if tinted then c(entry[2]) else white })
		rule(selector .. ".facet-skinned", {
			BackgroundTransparency = if tinted or pressed then 1 else 0,
			TextColor3 = if pressed then onSelected else nil,
		})
		rule(selector .. " > #SkinBoundary", { Visible = tinted or pressed })
		local swapped = pressed and selectedLink ~= nil and art ~= nil
		rule(
			selector .. " > #SkinBoundary >> #control" .. math.max(selectedLayer, 1),
			if swapped
					and selectedLink
					and art
				then {
					Image = art.content or art.contentId or "",
					Rotation = selectedLink.rotation or 0,
					ImageColor3 = color(types, selectedLink.tint) or white,
				}
				else {}
		)
		rule(selector .. ".facet-skinned >> .facet-button-caption", if swapped then { TextColor3 = onSelected } else {})
		rule(selector .. ".facet-skinned >> .facet-text", if swapped then { TextColor3 = onSelected } else {})
		rule(selector .. ".facet-skinned >> .facet-icon", if swapped then { ImageColor3 = onSelected } else {})
	end
	rule(".facet-toggle-checkbox.facet-skinned::UIStroke", { Transparency = 1 })
	rule(".facet-menu.facet-skinned::UIStroke", { Transparency = 1 })
	rule(".facet-segment-current.facet-skinned", if selectedArt then {} else { BackgroundTransparency = 0 })
	rule(".facet-segment-current > #SkinBoundary", if selectedArt then {} else { Visible = false })
	rule(".facet-segment-fill", if selectedArt then { Visible = false } else {})
	rule(".facet-segmented-slides > .facet-segment-current", if selectedArt then {} else { BackgroundTransparency = 1 })
	local authoredSelection = false
	for _, theme in package.style.themes do
		if type(theme.extra) == "table" and theme.extra.selection ~= nil then
			authoredSelection = true
		end
	end
	local markPlate = if authoredSelection then c("selection") else c("controlSelected")
	local markInk = if authoredSelection then c("onSelection") else onSelected
	local markStates: { string } = if authoredSelection then { "", ":Hover", ":Press" } else { "" }
	for _, suffix in markStates do
		rule(".facet-selection-mark.facet-selected" .. suffix, { BackgroundColor3 = markPlate, TextColor3 = markInk })
	end
	rule(".facet-selection-mark.facet-selected >> .facet-button-caption", { TextColor3 = markInk })
	rule(".facet-selection-mark.facet-selected >> .facet-text", { TextColor3 = markInk })
	rule(".facet-selection-mark.facet-selected >> .facet-icon", { ImageColor3 = markInk })
	if authoredSelection then
		local linkInk = c("selection")
		rule(".facet-appearance-link.facet-selected", { TextColor3 = linkInk })
		rule(".facet-appearance-link.facet-selected >> .facet-button-caption", { TextColor3 = linkInk })
		rule(".facet-appearance-link.facet-selected >> .facet-text", { TextColor3 = linkInk })
		rule(".facet-appearance-link.facet-selected >> .facet-icon", { ImageColor3 = linkInk })
	end
	if extra.dimDisabledPlates ~= true and extra.dimDisabledPlates ~= false then
		rule(".facet-button.facet-disabled", { BackgroundTransparency = 0.6 })
	end
	if extra.dimDisabledPlates == true then
		local dim = extra.disabledContentOpacity or 0.4
		local page = source("surface")
		local function faded(role: string): (Color3 | string)?
			local plate, base = source(role), page
			if plate == nil or base == nil then
				return c(role)
			end
			return kit.derived(
				role .. "Disabled",
				types.Color3.new(
					plate.r + (base.r - plate.r) * dim,
					plate.g + (base.g - plate.g) * dim,
					plate.b + (base.b - plate.b) * dim
				)
			)
		end
		for _, entry in
			{
				{ ".facet-button.facet-disabled", "control" },
				{ ".facet-button.facet-selected.facet-disabled", "controlSelected" },
				{ ".facet-accent.facet-disabled", "accent" },
				{ ".facet-appearance-soft.facet-disabled", "accent" },
				{ ".facet-appearance-inverse.facet-disabled", "inverseSurface" },
				{ ".facet-role-destructive.facet-disabled", "danger" },
				{ ".facet-disabled >> .facet-toggle-indicator", "control" },
				{ ".facet-disabled >> .facet-toggle-on", "selection" },
			}
		do
			rule(entry[1], { BackgroundColor3 = faded(entry[2]) })
		end
		rule(".facet-appearance-utility.facet-disabled", { BackgroundColor3 = c("surface") })
		if authoredSelection then
			rule(".facet-selection-mark.facet-selected.facet-disabled", { BackgroundColor3 = faded("selection") })
		end
	end
	do
		local on = selectedArt ~= nil
		local tint = if selectedLink then selectedLink.tint else nil
		rule(
			".facet-skinned.facet-selected",
			if on then { BackgroundTransparency = 1, TextColor3 = onSelected } else {}
		)
		rule(".facet-skinned.facet-selected > #SkinBoundary", if on then { Visible = true } else {})
		rule(
			".facet-skinned.facet-selected > #SkinBoundary >> .facet-skin-art",
			if on then { ImageColor3 = color(types, tint) or types.Color3.new(1, 1, 1) } else {}
		)
		rule(".facet-skinned.facet-selected >> .facet-button-caption", if on then { TextColor3 = onSelected } else {})
		rule(".facet-skinned.facet-selected >> .facet-text", if on then { TextColor3 = onSelected } else {})
		rule(".facet-skinned.facet-selected >> .facet-icon", if on then { ImageColor3 = onSelected } else {})
	end
	rule(".facet-selected >> .facet-text.facet-field", { TextColor3 = c("content") })
	rule(".facet-selected >> .facet-text-input >> .facet-text", { TextColor3 = c("content") })
	rule(".facet-tab-filled.facet-skinned", if selectedArt then {} else { BackgroundTransparency = 0 })
	rule(".facet-tab-filled > #SkinBoundary", if selectedArt then {} else { Visible = false })
	rule(".facet-button-outside, .facet-button-outside >> .facet-text", { TextColor3 = c("content") })
	rule(".facet-button-outside >> .facet-shortcut-glyph", { ImageColor3 = c("contentStrong") })
	for _, pair in
		{
			{ "facet-accent", "onAccent", "accent" },
			{ "facet-role-destructive", "onDanger", "danger" },
			{ "facet-appearance-inverse", "onInverse", "inverseSurface" },
		}
	do
		local ink, background = color(types, source(pair[2])), color(types, source(pair[3]))
		if ink and background then
			if extra.dimDisabledPlates then
				local surface = color(types, source("surface"))
				if surface then
					background = background:Lerp(surface, extra.disabledContentOpacity or 0.4)
				end
			end
			local opacity = support.readableTransparency(ink, background, extra.disabledContentOpacity or 0.4)
			local selector = "." .. pair[1] .. ".facet-disabled"
			rule(
				selector .. ", " .. selector .. " >> .facet-button-caption, " .. selector .. " >> .facet-text",
				{ TextTransparency = opacity }
			)
		end
	end
	return kit.finish()
end

local bound: { [typeof(ComposeTypes)]: ThemeTypes.Themes } = {}
setmetatable(bound, { __mode = "k" })

return function(Compose: typeof(ComposeTypes)): ThemeTypes.Themes
	local cached = bound[Compose]
	if cached then
		return cached
	end
	local surface: ThemeTypes.Themes = {
		SCHEMA = themes.SCHEMA,
		TYPE_ROLES = themes.TYPE_ROLES,
		REQUIRED_TYPE_ROLES = themes.REQUIRED_TYPE_ROLES,
		neutralPackage = themes.neutralPackage,
		forDistance = themes.forDistance,
		define = themes.define,
		checkCoverage = themes.checkCoverage,
		resolveIcon = themes.resolveIcon,
		createStyleSheet = function(
			runtime: ComposeTypes.Runtime,
			packageOrReadable: Engine.Input<ThemeTypes.ThemePackage>?,
			options: ThemeTypes.ThemeOptions?
		): StyleSheet
			return createStyleSheet(neutral, rulesFor, themes.forDistance, Compose, runtime, packageOrReadable, options)
		end,
		skin = function(
			runtime: ComposeTypes.Runtime,
			packageOrReadable: Engine.Input<ThemeTypes.ThemePackage>?,
			slot: string,
			options: ThemeTypes.SkinOptions?
		): Frame
			return skin(neutral, paint, Compose, runtime, packageOrReadable, slot, options)
		end,
	}
	bound[Compose] = surface
	return surface
end
