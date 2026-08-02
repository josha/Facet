--!strict
-- TEST FIXTURE THEME PACKAGE — "Content A/B" (rich-skinning-v2 package P4).
--
-- NOT a reference package. It exists for exactly one proposition (ADR-0020 R6):
-- `content` is the canonical asset field and `contentId` is a kept alias, and
-- the two are ONE resolution path rather than two that happen to agree today.
--
-- The two builds below differ in NOTHING except which of the two names each
-- asset uses. Everything else — identity, palette, metrics, recipes, icon map —
-- is the same table, produced by the same function. So:
--
--   * their compiled `assets` and their content STAMPS are equal (the stamp is a
--     hash over the compiled data, so equal stamps IS byte-equality);
--   * their emitted rules are equal, prop for prop;
--   * a live A/B paints identically, read back through `GetStyled` on the same
--     node under each — which is the half a headless comparison cannot see.
--
-- Authored and exported data stay PLAIN STRINGS either way. rs-m7 measured that
-- the engine coerces a string on an `ImageContent` rule, and that even a
-- `Content.fromUri` rule round-trips as a string, so there is no materialization
-- shim anywhere in the framework and packages stay serializable.
--
-- ART: one PNG from the repository's own `assets/themes/pixel-quest/` set
-- (provenance in that folder), reused rather than re-uploaded.

local content_alias_test = {}

content_alias_test.id = "content-ab-test"
content_alias_test.displayName = "Content A/B"
content_alias_test.themeClasses = table.freeze({ "palette", "assets" })
content_alias_test.testOnly = true

local PLATE = "rbxassetid://70509734376718" -- pixel_plate_default
local GLYPH = "rbxassetid://137937473154830" -- pixel_icon_plus

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local THEME = {
	colors = {
		surface = rgb(22, 18, 31),
		surfaceStrong = rgb(58, 44, 79),
		content = rgb(244, 230, 192),
		contentStrong = rgb(255, 250, 235),
		accent = rgb(79, 168, 63),
		onAccent = rgb(22, 18, 31),
		danger = rgb(122, 31, 34),
		onDanger = rgb(244, 230, 192),
	},
	extra = { control = rgb(168, 114, 47), contentSecondary = rgb(215, 168, 96) },
}

-- `field` is the ONE name that differs between the two builds.
local function definition(themes: any, field: string): any
	local function asset(contentValue: string, extra: any?): any
		local out: any = { preload = "install", fallback = "native" }
		out[field] = contentValue
		for key, value in extra or {} do
			out[key] = value
		end
		return out
	end
	return {
		base = themes.neutralPackage(),
		identity = {
			-- deliberately the SAME id and version in both builds: the packages are
			-- meant to be indistinguishable, and a differing identity would make
			-- the stamp comparison vacuous
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
		compatibility = { requiresSchema = themes.SCHEMA },
	}
end

-- A: the canonical field.
function content_alias_test.build(themes: any): (any, any)
	return themes.define(definition(themes, "content"))
end

-- B: the kept alias. Same package, older spelling.
function content_alias_test.buildAlias(themes: any): (any, any)
	return themes.define(definition(themes, "contentId"))
end

content_alias_test.definition = definition

return content_alias_test
