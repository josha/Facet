--!strict
-- REFERENCE THEME PACKAGE — "Classic Desktop".
--
-- A compact, square-edged, flat workstation look: hairline strokes, dense
-- metrics, no gradients, no assets. It exists to prove the *metric* half of the
-- theme contract — a package that changes nothing but numbers still has to move
-- every control's geometry — and to carry the PALETTE-ONLY case, because its
-- two themes ("Day" and "Night") differ in colour and in nothing else, so a
-- `swapTheme` between them must repaint without re-solving a single dimension.
--
-- ORIGINAL WORK. The palette is a neutral warm-grey ramp chosen here; it is not
-- sampled from, and does not imitate the trade dress of, any shipping operating
-- system. There are no bundled assets of any kind — this package declares none.
--
-- Written against the PUBLIC API only: `themes.neutralPackage()` for the
-- derivation base and `themes.define` for compilation. Nothing here requires a
-- LuauUI internal module, which is the point — a game team can copy this file.

local classic_desktop = {}

classic_desktop.id = "classic-desktop"
classic_desktop.displayName = "Classic Desktop"
-- the theme classes this package exercises (the coverage matrix asserts these
-- against a real diff of the compiled package, so a stale claim fails the suite)
classic_desktop.themeClasses = table.freeze({ "palette", "metrics" })

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

-- One typography ladder, shared by both themes: this package's whole point is
-- that a palette swap moves nothing geometric.
local FAMILY = "rbxasset://fonts/families/BuilderSans.json"
local LINE_HEIGHT = 1.15
local SIZES = { caption = 11, label = 12, body = 13, control = 13, heading = 15, title = 18 }

local function typography(): any
	local out: any = {}
	for role, size in SIZES do
		out[role] = { font = { family = FAMILY }, size = size, lineHeight = LINE_HEIGHT }
	end
	return out
end

-- Day: paper-white content area on a warm grey chrome.
local DAY = {
	colors = {
		surface = rgb(212, 208, 200),
		surfaceStrong = rgb(240, 238, 232),
		content = rgb(24, 24, 24),
		contentStrong = rgb(8, 8, 8),
		accent = rgb(16, 54, 122),
		onAccent = rgb(255, 255, 255),
		danger = rgb(140, 20, 20),
		onDanger = rgb(255, 255, 255),
	},
	extra = {
		control = rgb(226, 223, 216),
		controlHover = rgb(238, 236, 230),
		controlPressed = rgb(198, 194, 186),
		controlSelected = rgb(180, 198, 226),
		contentSecondary = rgb(88, 88, 88),
		hairline = rgb(96, 94, 90), -- a light theme needs a DARK hairline
		hairlineOpacity = 0.55,
		scrimOpacity = 0.4,
		disabledContentOpacity = 0.45,
	},
}

-- Night: the identical ladder on an inverted ramp. Same metrics, same fonts.
local NIGHT = {
	colors = {
		surface = rgb(38, 38, 36),
		surfaceStrong = rgb(52, 52, 49),
		content = rgb(232, 230, 224),
		contentStrong = rgb(250, 249, 245),
		accent = rgb(122, 168, 236),
		onAccent = rgb(12, 16, 26),
		danger = rgb(228, 116, 116),
		onDanger = rgb(28, 10, 10),
	},
	extra = {
		control = rgb(64, 64, 60),
		controlHover = rgb(78, 78, 73),
		controlPressed = rgb(48, 48, 45),
		controlSelected = rgb(56, 74, 104),
		contentSecondary = rgb(168, 166, 158),
		hairline = rgb(255, 255, 255),
		hairlineOpacity = 0.86,
		scrimOpacity = 0.5,
		disabledContentOpacity = 0.45,
	},
}

function classic_desktop.definition(themes: any): any
	return {
		base = themes.neutralPackage(),
		identity = {
			id = classic_desktop.id,
			displayName = classic_desktop.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = {
			defaultTheme = "Day",
			themes = {
				{ name = "Day", colors = DAY.colors, extra = DAY.extra },
				{ name = "Night", colors = NIGHT.colors, extra = NIGHT.extra },
			},
		},
		metrics = {
			typography = typography(),
			-- dense: roughly half the neutral spacing ladder
			space = { xs = 2, s = 4, m = 8, l = 12, xl = 20 },
			-- rows a mouse can hit precisely. The 44px accessibility floor still
			-- applies to the HIT rect (the presenter expands it); these are the
			-- painted heights, and a desktop theme is allowed to paint tighter.
			controlSizes = {
				compact = { height = 22, paddingX = 6, iconSize = 12 },
				regular = { height = 26, paddingX = 8, iconSize = 14 },
				large = { height = 32, paddingX = 10, iconSize = 16 },
			},
			-- square-edged: 0 for panels, a 2px softening on controls so a
			-- pressed button still reads as a button
			radii = { control = 2, panel = 0, pill = 4 },
			strokes = { hairline = 1 },
			targetSizes = { minimum = 44 },
			-- snappier than neutral: a desktop control should feel instant
			motion = { fast = 0.06, normal = 0.1 },
			-- the slot insets a flat theme reserves (no asset geometry to clear)
			insets = {
				panel = { top = 8, right = 8, bottom = 8, left = 8 },
				control = { top = 4, right = 8, bottom = 4, left = 8 },
				field = { top = 4, right = 8, bottom = 4, left = 8 },
				selection = { top = 2, right = 4, bottom = 2, left = 4 },
				divider = { top = 0, right = 0, bottom = 0, left = 0 },
				scrollbar = { top = 0, right = 0, bottom = 0, left = 0 },
			},
		},
		-- every slot is native paint: ZERO decoration instances
		chrome = {
			panel = { kind = "native" },
			control = { kind = "native" },
			field = { kind = "native" },
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},
		assets = {},
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

function classic_desktop.build(themes: any): (any, any)
	return themes.define(classic_desktop.definition(themes))
end

return classic_desktop
