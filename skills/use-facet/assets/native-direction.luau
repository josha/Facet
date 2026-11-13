--!strict

local Facet = require(game.ReplicatedStorage.Packages.Facet)
local C = Facet.Compose
local function rgb(r: number, g: number, b: number): Facet.RGB
	return { r = r / 255, g = g / 255, b = b / 255 }
end

local paper = rgb(255, 247, 231)
local vermilion = rgb(156, 40, 30)
local ultramarine = rgb(36, 58, 131)
local serif = { family = "Merriweather", weight = "Bold" }
local definition: Facet.ThemeDefinition = {
	identity = { id = "proof-press", displayName = "Proof Press" },
	style = {
		defaultTheme = "Paper",
		themes = {
			{
				name = "Paper",
				colors = {
					surface = rgb(235, 218, 191),
					surfaceStrong = paper,
					content = rgb(41, 32, 22),
					accent = vermilion,
					onAccent = paper,
				},
				extra = {
					control = rgb(241, 227, 206),
					contentSecondary = rgb(90, 68, 52),
					controlSelected = rgb(41, 32, 22),
					onSelected = paper,
					chromeGradient = {
						surface = {
							rotation = 90,
							stops = { { t = 0, r = 1, g = 1, b = 1 }, { t = 1, r = 0.8, g = 0.73, b = 0.64 } },
						},
					},
				},
			},
		},
	},
	metrics = {
		typography = {
			title = { size = 42, font = serif },
			heading = { size = 26, font = serif },
			numeral = { size = 26, font = serif },
			control = { size = 18, font = { weight = "Bold" } },
		},
		radii = { panel = 0, control = 4 },
	},
	finish = {
		edge = { width = 2, role = "content" },
		depth = { lift = 3, blur = 8, glow = 0, sheen = 0 },
	},
	chrome = {
		focus = { kind = "ring", thickness = 3, color = rgb(97, 54, 99) },
	},
}
local theme, report = Facet.themes.define(definition)
assert(theme, report.errors[1] and report.errors[1].message)

local app = Facet.app({ name = "ProofPress", theme = theme })
local UI = app.UI
local draft = C.cell("Ultramarine")
local printed = C.cell("Ultramarine")
local pulls = C.cell(1)

local function choice(ink: string, grow: boolean)
	return UI.Button {
		label = ink,
		selected = function(use: Facet.Use)
			return use(draft) == ink
		end,
		trailingIcon = function(use: Facet.Use)
			return if use(draft) == ink then "checkmark" else ""
		end,
		onActivate = function()
			draft:set(ink)
		end,
		if grow then UI.fill() else nil,
	}
end

local function pull()
	return UI.Button "Print" {
		label = "Pull a proof",
		appearance = "emphasis",
		onActivate = function()
			printed:set(draft:peek())
			pulls:update(function(count: number): number
				return count + 1
			end)
		end,
	}
end

app.mount(function()
	local env = UI.environment()
	local function sheetWidth(use: Facet.Use): number
		return math.floor(use(env.viewportHeight) * 1.1)
	end
	local function ink(use: Facet.Use): Color3
		local color = if use(printed) == "Vermilion" then vermilion else ultramarine
		return Color3.new(color.r, color.g, color.b)
	end

	local function sheet()
		return UI.VStack "Sheet" {
			surface = "panel",
			width = "fill",
			height = "fill",
			maxWidth = sheetWidth,
			padding = "l",
			gap = "s",
			align = "center",
			distribute = "center",
			UI.fill(),
			UI.Text "Specimen" {
				text = "Pack my box.",
				textRole = "title",
				textSize = { fit = { cap = 100, floor = 34 } },
				textAlign = "center",
				Size = UDim2.fromScale(1, 0.3),
				tint = ink,
			},
			UI.Text { text = "with five dozen", textRole = "title", textAlign = "center", wrap = true, tint = ink },
			UI.Text { text = "liquor jugs.", textRole = "heading", textAlign = "center", wrap = true, tint = ink },
			UI.Divider {},
			UI.HStack "Imprint" {
				gap = "m",
				align = "center",
				UI.Text {
					text = function(use: Facet.Use)
						return "No. " .. use(pulls)
					end,
					textRole = "numeral",
				},
				UI.Text {
					text = function(use: Facet.Use)
						return "Printed in " .. use(printed)
					end,
					textRole = "caption",
				},
			},
		}
	end

	return C.show(env.isLandscape, function()
		return UI.Screen "ProofPress" {
			surface = "surface",
			UI.HStack "Bed" {
				width = "fill",
				height = "fill",
				gap = "m",
				distribute = "center",
				UI.fill(),
				sheet(),
				UI.VStack "Rail" {
					surface = "panel",
					width = 260,
					padding = "s",
					gap = "s",
					align = "stretch",
					UI.Text { text = "Proof press", textRole = "heading" },
					choice("Vermilion", false),
					choice("Ultramarine", false),
					pull(),
				},
			},
		}
	end, function()
		return UI.Screen "ProofPress" {
			surface = "surface",
			gap = "m",
			UI.Text { text = "Proof press", textRole = "heading" },
			sheet(),
			UI.VStack "Rail" {
				surface = "panel",
				width = "fill",
				padding = "s",
				gap = "s",
				align = "stretch",
				UI.HStack "Inks" {
					width = "fill",
					gap = "s",
					choice("Vermilion", true),
					choice("Ultramarine", true),
				},
				pull(),
			},
		}
	end)
end)
script.Destroying:Connect(app.dispose)
