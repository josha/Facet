--!strict
local ComposeTypes = require("../vendor/compose/core")
local ControlTypes = require("./control_types")

type Compose = typeof(ComposeTypes)

return function(UI: ControlTypes.Controls, Compose: Compose): Instance
	local function pressed() end
	local function fact(value: string, caption: string): Instance
		return UI.VStack {
			gap = "xs",
			UI.Text { text = value, textRole = "numeral" },
			UI.Text { text = caption, textRole = "caption" },
		}
	end
	local function record(name: string, state: string, mark: string): Instance
		return UI.HStack {
			surface = "surface",
			padding = "s",
			gap = "m",
			width = "fill",
			align = "center",
			UI.VStack {
				UI.fill(),
				gap = "xs",
				UI.Text { text = name, textRole = "strong" },
				UI.Text { text = state, textRole = "caption" },
			},
			UI.Badge { label = mark },
		}
	end
	local choices =
		{ { value = "one", label = "One" }, { value = "two", label = "Two" }, { value = "three", label = "Three" } }
	return UI.VStack "Specimen" {
		width = "fill",
		height = "fill",
		surface = "surface",
		padding = "l",
		gap = "l",
		UI.Text { text = "Title of the screen", textRole = "title" },
		UI.HStack "Plates" {
			gap = "l",
			wrap = true,
			width = "fill",
			UI.VStack "Type" {
				surface = "panel",
				padding = "m",
				gap = "s",
				width = 360,
				UI.Text { text = "Heading", textRole = "heading" },
				UI.HStack { gap = "l", fact("1,250", "Caption"), fact("3rd", "Place") },
				UI.Text { text = "Strong text", textRole = "strong" },
				UI.Text { text = "Body text reads as a sentence and wraps inside its plate.", wrap = true },
				UI.Text { text = "LABEL", textRole = "label" },
			},
			UI.VStack "Actions" {
				surface = "panel",
				padding = "m",
				gap = "s",
				width = 300,
				align = "stretch",
				UI.Text { text = "Actions", textRole = "heading" },
				UI.Button { label = "Main action", appearance = "emphasis", onActivate = pressed },
				UI.Button { label = "Action", onActivate = pressed },
				UI.Button { label = "Disabled", enabled = false, onActivate = pressed },
				UI.Toggle { label = "Setting", value = Compose.cell(true), onChange = pressed },
				UI.TextInput { value = Compose.cell(""), placeholder = "Field" },
			},
			UI.VStack "Records" {
				surface = "panel",
				padding = "m",
				gap = "s",
				width = 360,
				UI.Text { text = "Records", textRole = "heading" },
				record("First record", "Owned", "Ready"),
				record("Second record", "600 to unlock", "New"),
				UI.Picker { selected = Compose.cell("one"), options = choices, style = "segmented" },
			},
		},
	}
end
