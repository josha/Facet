--!strict
type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)
type ThemeDefinition = typeof(require("@repo/tools/typecheck/aliases").ThemeDefinition)
type Extra = typeof(require("@repo/tools/typecheck/aliases").ThemePackage.style.themes[1].extra)
type Asset = typeof(require("@repo/tools/typecheck/aliases").ThemeAsset)
type RGB = { r: number, g: number, b: number }
type Palette = { colors: { [string]: RGB }, extra: Extra }

local content_alias_test = {}

content_alias_test.id = "content-ab-test"
content_alias_test.displayName = "Content A/B"
content_alias_test.themeClasses = table.freeze({ "palette", "assets" })
content_alias_test.testOnly = true

local PLATE = "rbxassetid://70509734376718"
local GLYPH = "rbxassetid://137937473154830"

local function rgb(r: number, g: number, b: number): RGB
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local THEME: Palette = {
	colors = {
		surface = rgb(22, 18, 31),
		surfaceStrong = rgb(58, 44, 79),
		content = rgb(244, 230, 192),
		contentStrong = rgb(255, 250, 235),
		accent = rgb(79, 168, 63),
		onAccent = rgb(22, 18, 31),
		danger = rgb(122, 31, 34),
		onDanger = rgb(244, 230, 192),

		success = rgb(42, 104, 46),
		onSuccess = rgb(244, 230, 192),
		warning = rgb(200, 148, 52),
		onWarning = rgb(22, 18, 31),
	},
	extra = { control = rgb(168, 114, 47), contentSecondary = rgb(215, 168, 96) },
}

local function definition(themes: Themes, field: "content" | "contentId"): ThemeDefinition
	local function asset(contentValue: string, extra: Asset): Asset
		local out = table.clone(extra)
		out.preload = "install"
		out.fallback = "native"
		if field == "content" then
			out.content = contentValue
		else
			out.contentId = contentValue
		end
		return out
	end
	return {
		base = themes.neutralPackage(),
		identity = {

			id = content_alias_test.id,
			displayName = content_alias_test.displayName,
			schemaVersion = themes.SCHEMA,
			version = "1.0.0",
		},
		style = { defaultTheme = "AB", themes = { { name = "AB", colors = THEME.colors, extra = THEME.extra } } },
		chrome = {
			control = {
				kind = "nineSlice",
				asset = "plate",
				fallback = "native",
				contentInsets = { top = 16, right = 16, bottom = 16, left = 16 },
			},
			panel = { kind = "native" },
			field = { kind = "native" },
			selection = { kind = "native" },
			divider = { kind = "native" },
			scrollbar = { kind = "native" },
		},
		icons = { increment = "glyph" },
		assets = {
			plate = asset(PLATE, {
				sliceCenter = { x0 = 16, y0 = 16, x1 = 20, y1 = 20 },
				sliceScale = 1,
			}),
			glyph = asset(GLYPH, { tintRole = "accent" }),
		},
	}
end

function content_alias_test.build(themes: Themes)
	return themes.define(definition(themes, "content"))
end

function content_alias_test.buildAlias(themes: Themes)
	return themes.define(definition(themes, "contentId"))
end

content_alias_test.definition = definition

return content_alias_test
