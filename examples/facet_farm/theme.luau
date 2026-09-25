--!strict
local theme = {}

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

theme.ART = table.freeze({
	meadow = rgb(214, 228, 176),
	grass = rgb(118, 168, 82),
	grassEdge = rgb(92, 140, 64),
	soilEdge = rgb(84, 58, 38),
	furrow = rgb(88, 60, 40),
	fence = rgb(150, 104, 62),
	fenceEdge = rgb(110, 74, 42),
	board = rgb(126, 176, 88),
	plowed = rgb(122, 86, 58),
	growing = rgb(104, 74, 50),
	withered = rgb(96, 88, 74),
	sprout = rgb(92, 178, 74),
	stalk = rgb(72, 140, 58),
	wheat = rgb(232, 192, 88),
	carrot = rgb(236, 128, 44),
	strawberry = rgb(214, 52, 66),
	pumpkin = rgb(232, 118, 34),
	dry = rgb(150, 120, 80),
})

function theme.color(Color3: any, name: string): Color3
	local value = theme.ART[name]
	return Color3.new(value.r, value.g, value.b)
end

function theme.create(Facet: any)
	local themes = Facet.themes
	local package, report = themes.define({
		base = themes.neutralPackage(),
		identity = { id = "facet-farm", displayName = "Facet Farm", schemaVersion = 1, version = "1.0.0" },
		style = {
			defaultTheme = "Meadow",
			themes = {
				{
					name = "Meadow",
					colors = {
						surface = rgb(246, 239, 222),
						surfaceStrong = rgb(255, 251, 240),
						content = rgb(58, 46, 32),
						contentStrong = rgb(38, 30, 20),
						accent = rgb(62, 128, 60),
						onAccent = rgb(255, 255, 255),
						danger = rgb(170, 48, 40),
						onDanger = rgb(255, 255, 255),
					},
					extra = {
						control = rgb(234, 222, 196),
						controlHover = rgb(224, 210, 180),
						controlPressed = rgb(212, 196, 164),
						controlSelected = rgb(62, 128, 60),
						onSelected = rgb(255, 255, 255),
						contentSecondary = rgb(112, 96, 72),
						hairline = rgb(196, 180, 150),
						hairlineOpacity = 0,
					},
				},
			},
		},
		metrics = {
			space = { xs = 4, s = 8, m = 14, l = 22, xl = 32 },
			radii = { control = 12, panel = 18, pill = 999 },
		},
	})
	assert(package, if report.errors[1] then report.errors[1].message else "Facet Farm theme is invalid")
	return package
end

return theme
