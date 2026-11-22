--!strict

type Themes = typeof(require("@repo/tools/typecheck/aliases").FacetModule.themes)
type ThemeDefinition = typeof(require("@repo/tools/typecheck/aliases").ThemeDefinition)
type PalettePatch = typeof(require("@repo/tools/typecheck/aliases").PalettePatch)

local DEFINITIONS: { [string]: ThemeDefinition } = {
	flat = {
		identity = { id = "look-flat", displayName = "Look: flat" },
		finish = {
			look = "flat",
			depth = { controls = { lift = 3, side = 0, shade = 0.35 } },
			plates = { row = { edge = { width = 1, transparency = 0.4 } } },
		},
		motion = { feel = "crisp" },
	},
	raised = {
		identity = { id = "look-raised", displayName = "Look: raised" },
		finish = { look = "raised", plates = { row = { depth = { lift = 3 } } } },
		motion = { feel = "calm" },
	},
	glow = {
		identity = { id = "look-glow", displayName = "Look: glow" },
		finish = { look = "glow", plates = { row = { edge = { width = 1 }, depth = { glow = 10 } } } },
		motion = { feel = "crisp" },
	},
	hard = {
		identity = { id = "look-hard", displayName = "Look: hard" },
		finish = {
			look = "hard",
			depth = { controls = { side = 0, shade = 0.45 } },
			plates = { row = { edge = { width = 2 }, depth = { lift = 3, side = 0 } } },
		},
		motion = { feel = "lively" },
	},
}

local looks = {}

function looks.make(themes: Themes, name: string)
	local definition = table.clone(assert(DEFINITIONS[name], "unknown look"))
	local neutral = themes.neutralPackage().style
	local palettes: { PalettePatch } = {}
	for _, palette in neutral.themes do
		table.insert(palettes, { name = palette.name, colors = palette.colors, extra = palette.extra })
	end
	definition.style = { defaultTheme = neutral.defaultTheme, themes = palettes }
	local package, report = themes.define(definition)
	return assert(package, report.errors[1] and report.errors[1].message)
end

return looks
