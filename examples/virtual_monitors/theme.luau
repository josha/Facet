--!strict
local theme = {}
theme.ICONS = table.freeze({
	"facet:search",
	"person",
	"edit",
	"checkmark",
	"increment",
	"close",
	"chevron.up",
	"chevron.leading",
	"vote.up",
	"vote.down",
	"status.info",
})
theme.NEEDS = table.freeze({
	{ name = "contentSecondary", kind = "color" },
	{ name = "hairline", kind = "color" },
	{ name = "controlSelected", kind = "color" },
	{ name = "panel", section = "metrics.radii", kind = "number" },
	{ name = "l", section = "metrics.space", kind = "number" },
})
local function rgb(r, g, b)
	return { r = r / 255, g = g / 255, b = b / 255 }
end
theme.ACCENTS = table.freeze({
	table.freeze({ id = "sage", label = "Sage", light = rgb(45, 86, 65), dark = rgb(144, 220, 190) }),
	table.freeze({ id = "clay", label = "Clay", light = rgb(158, 66, 38), dark = rgb(244, 172, 140) }),
	table.freeze({ id = "iris", label = "Iris", light = rgb(91, 70, 140), dark = rgb(192, 172, 255) }),
})
function theme.paletteName(accent: string, dark: boolean): string
	local mode = if dark then "Dark" else "Light"
	for index, entry in theme.ACCENTS do
		if entry.id == accent and index > 1 then
			return entry.label .. " " .. mode
		end
	end
	return mode
end
function theme.create(Facet: any, name: string)
	local themes = Facet.themes
	local function palette(entry, dark)
		local accent = if dark then entry.dark else entry.light
		return {
			name = theme.paletteName(entry.id, dark),
			colors = {
				surface = if dark then rgb(18, 17, 26) else rgb(243, 240, 233),
				surfaceStrong = if dark then rgb(32, 30, 44) else rgb(255, 255, 255),
				content = if dark then rgb(233, 229, 244) else rgb(45, 46, 42),
				contentStrong = if dark then rgb(255, 253, 255) else rgb(26, 32, 29),
				accent = accent,
				onAccent = if dark then rgb(28, 22, 46) else rgb(255, 255, 255),
				danger = if dark then rgb(255, 166, 166) else rgb(161, 39, 46),
				onDanger = if dark then rgb(42, 15, 15) else rgb(255, 255, 255),
			},
			extra = {
				pressedScale = 1,
				control = if dark then rgb(58, 54, 80) else rgb(232, 230, 223),
				controlHover = if dark then rgb(74, 68, 100) else rgb(222, 221, 212),
				controlPressed = if dark then rgb(86, 78, 114) else rgb(211, 214, 203),
				controlSelected = accent,
				onSelected = if dark then rgb(28, 22, 46) else rgb(255, 255, 255),
				contentSecondary = if dark then rgb(174, 168, 188) else rgb(102, 105, 94),
				hairline = if dark then rgb(66, 61, 88) else rgb(189, 191, 178),
			},
		}
	end
	local sizes =
		{ caption = 13, label = 16, body = 19, control = 17, heading = 25, title = 34, strong = 19, numeral = 17 }
	local typography = {}
	for role, entry in themes.neutralPackage().metrics.typography do
		typography[role] = { font = entry.font, size = sizes[role] or entry.size, lineHeight = 1.25 }
	end
	local palettes = {}
	for _, entry in theme.ACCENTS do
		table.insert(palettes, palette(entry, false))
		table.insert(palettes, palette(entry, true))
	end
	local package, report = themes.define({
		identity = {
			id = "virtual-monitors-" .. string.lower(name),
			displayName = "Virtual Monitors / " .. name,
			schemaVersion = 1,
			version = "1.2.0",
		},
		style = { defaultTheme = "Dark", themes = palettes },
		metrics = {
			motion = { fast = 0.12, normal = 0.32 },
			typography = typography,
			space = { xs = 4, s = 8, m = 14, l = 22, xl = 32 },
			radii = { control = 12, panel = 18, pill = 999 },
		},
		chrome = { monitorPanel = { kind = "native", shadow = "raised" } },
	})
	assert(package, if report.errors[1] then report.errors[1].message else "Virtual Monitors theme is invalid")
	local coverage = themes.checkCoverage(package, theme.NEEDS)
	for _, gap in coverage.missing do
		warn(`Virtual Monitors theme {name}: {gap.message}. {gap.fix}.`)
	end
	for _, icon in theme.ICONS do
		if themes.resolveIcon(package, icon) == nil then
			warn(`Virtual Monitors theme {name}: no artwork for the {icon} icon.`)
		end
	end
	return package, report
end

return theme
