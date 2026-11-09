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
					controlSelected = ultramarine,
					onSelected = paper,
				},
			},
		},
	},
	metrics = {
		typography = {
			title = { size = 42, font = serif },
			heading = { size = 26, font = serif },
			control = { size = 18, font = { weight = "Bold" } },
		},
		radii = { panel = 0, control = 4 },
	},
	chrome = {
		panel = { kind = "native", shadow = "raised" },
		focus = { kind = "ring", thickness = 3, color = rgb(97, 54, 99) },
	},
}
local theme, report = Facet.themes.define(definition)
assert(theme, report.errors[1] and report.errors[1].message)

local app = Facet.app({ name = "ProofPress", theme = theme })
local UI = app.UI
local draft = C.cell("Ultramarine")
local printed = C.cell("Ultramarine")
local function choice(ink: string)
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
	}
end

app.mount(function()
	return UI.Screen "ProofPress" {
		surface = "surface",
		align = "center",
		UI.ScrollView "Workshop" {
			width = "fill",
			maxWidth = 520,
			padding = "s",
			gap = "m",
			UI.fill(),
			UI.Text { text = "Proof press", textSize = "heading" },
			UI.VStack "Paper" {
				surface = "panel",
				width = "fill",
				padding = "m",
				gap = "xs",
				UI.Text {
					text = "Pack my box.",
					textSize = "title",
					wrap = true,
					tint = function(use: Facet.Use)
						local ink = if use(printed) == "Vermilion" then vermilion else ultramarine
						return Color3.new(ink.r, ink.g, ink.b)
					end,
				},
				UI.Text {
					text = function(use: Facet.Use)
						return "Printed in " .. use(printed)
					end,
					textSize = "caption",
				},
			},
			UI.HStack "Inks" {
				width = "fill",
				wrap = true,
				gap = "s",
				choice("Vermilion"),
				choice("Ultramarine"),
			},
			UI.Button "Print" {
				label = "Pull a proof",
				appearance = "emphasis",
				onActivate = function()
					printed:set(draft:peek())
				end,
			},
		},
	}
end)
script.Destroying:Connect(app.dispose)
