--!strict
local Facet = require(game:GetService("ReplicatedStorage").Packages.Facet)
local Art = require(script.Parent.Art)

local function rgb(r: number, g: number, b: number)
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local function image(id: string)
	return {
		contentId = id,
		sliceCenter = { x0 = 36, y0 = 26, x1 = 732, y1 = 130 },
		sliceScale = 0.48,
	}
end

return function(bakery: boolean, weak: boolean)
	if weak then
		return Facet.themes.neutralPackage()
	end
	local files = if bakery then Art.Bakery else Art.Drone
	local base = Facet.themes.neutralPackage()
	local cream, brown, berry = rgb(255, 242, 208), rgb(62, 29, 19), rgb(131, 27, 58)
	local steel, ink, amber = rgb(18, 26, 34), rgb(237, 243, 245), rgb(251, 170, 50)
	local foreground, background, accent = if bakery then brown else ink, if bakery then cream else steel, if bakery then berry else amber
	local foregroundAccent = if bakery then cream else steel
	local title = base.metrics.typography.title
	title.size = if bakery then 74 else 54
	title.font = if bakery
		then { family = "rbxasset://fonts/families/Guru.json", weight = "Bold" }
		else { family = "rbxasset://fonts/families/RobotoCondensed.json", weight = "Bold" }
	base.metrics.typography.control.font = title.font
	base.metrics.typography.control.size = if bakery then 32 else 25
	base.metrics.typography.heading.font = title.font
	base.metrics.typography.heading.size = 30
	base.metrics.typography.strong.font = title.font
	base.metrics.typography.strong.size = 23
	base.metrics.radii.control = if bakery then 9 else 3
	base.metrics.radii.panel = if bakery then 12 else 3
	base.metrics.controlSizes.large.paddingX = 13
	base.metrics.controlSizes.compact.paddingX = 8
	base.metrics.controlSizes.large.iconSize = if bakery then 53 else 20
	local light = rgb(254, 224, 163)
	local dark = rgb(38, 53, 63)
	local definition: Facet.ThemeDefinition = {
		base = base,
		identity = { id = if bakery then "first-light-bakery" else "relay-dispatch" },
		style = {
			defaultTheme = "Art",
			themes = {
				{
					name = "Art",
					colors = {
						surface = background,
						surfaceStrong = background,
						content = foreground,
						contentStrong = foreground,
						accent = accent,
						onAccent = foregroundAccent,
					},
					extra = {
						control = if bakery then light else dark,
						controlHover = if bakery then rgb(255, 229, 173) else rgb(52, 66, 77),
						controlPressed = if bakery then rgb(219, 180, 118) else rgb(32, 43, 53),
						controlSelected = if bakery then light else dark,
						onSelected = foreground,
						contentSecondary = if bakery then rgb(92, 51, 34) else rgb(196, 212, 220),
						hairline = if bakery then rgb(147, 98, 63) else rgb(104, 126, 136),
						scrimOpacity = 0.62,
						selection = accent,
						onSelection = foregroundAccent,
					},
				},
			},
		},
		assets = {
			choice = image(files.choice),
			action = { contentId = files.action },
			hero = { contentId = files.hero },
			paper = if bakery then { contentId = Art.Bakery.paper } else nil,
			ingredients = if bakery then { contentId = Art.Bakery.ingredients } else nil,
			portrait = if bakery then nil else { contentId = Art.Drone.portrait },
		},
		chrome = {
			control = {
				kind = "nineSlice",
				asset = {
					default = "choice",
					hover = { asset = "choice", tint = rgb(252, 245, 229) },
					pressed = { asset = "choice", tint = rgb(201, 196, 187) },
					selected = if bakery then { asset = "choice", tint = rgb(255, 225, 190) } else nil,
				},
				contentInsets = { left = 7, right = 7, top = if bakery then 4 else 1, bottom = 2 },
			},
			focus = if bakery
				then { kind = "ring", color = rgb(213, 139, 35), thickness = 2, outset = 3 }
				else { kind = "brackets", color = rgb(229, 245, 251), thickness = 2, outset = 3, size = 11 },
			panel = {
				kind = if bakery then "nineSlice" else "native",
				asset = if bakery then "choice" else nil,
				shadow = "raised",
				contentInsets = { left = 24, right = 24, top = 18, bottom = 18 },
			},
		},
		rules = {
			{
				selector = ".example-action::UIPadding",
				properties = { PaddingLeft = UDim.new(), PaddingRight = UDim.new(), PaddingTop = UDim.new(), PaddingBottom = UDim.new() },
			},
			{
				selector = ".drone-choice.facet-selected::UIStroke",
				properties = { Color = Color3.fromRGB(246, 161, 49), Thickness = 2, Transparency = 0 },
			},
			{ selector = ".example-action:Hover >> #ActionArt", properties = { ImageTransparency = 0.08 } },
			{ selector = ".example-action:Press >> #ActionArt", properties = { ImageTransparency = 0.29 } },
			{ selector = ".example-action.facet-disabled >> #ActionArt", properties = { ImageTransparency = 0.58 } },
			{ selector = ".example-action.facet-disabled >> #ActionLabel", properties = { TextTransparency = 0.45 } },
		},
	}
	local theme, report = Facet.themes.define(definition)
	if not report.ok then
		for _, issue in report.errors do
			warn(issue.field, issue.message)
		end
	end
	assert(theme and report.ok, "Example theme validation failed")
	return theme
end
