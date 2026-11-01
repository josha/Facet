--!strict
local FacetTypes = require("../../src")

type FacetModule = FacetTypes.Facet
type FacetControls = FacetTypes.Controls
type BooleanCell = FacetTypes.Value<boolean>
type NumberCell = FacetTypes.Value<number>
type StringCell = FacetTypes.Value<string>
type Model = { music: BooleanCell, volume: NumberCell, quality: StringCell, reset: () -> () }

return function(_Facet: FacetModule, UI: FacetControls, model: Model): Instance
	local options: { FacetTypes.PickerOption<string> } = {
		{ value = "low", label = "Low" },
		{ value = "medium", label = "Medium" },
		{ value = "high", label = "High" },
	}
	local pickerSpec: FacetTypes.SinglePickerSpec<string> = {
		label = "Quality",
		selected = model.quality,
		options = options,
	}
	return UI.Screen "Settings" {
		padding = "m",
		gap = "m",
		UI.Text "Title" { text = "Settings", textRole = "title" },
		UI.Toggle "Music" { label = "Music", value = model.music },
		UI.Slider "Volume" {
			label = "Volume",
			value = model.volume,
			min = 0,
			max = 100,
			step = 1,
			format = function(value)
				return `{value}%`
			end,
		},
		UI.Picker "Quality"(pickerSpec),
		UI.Button "Reset" {
			label = "Reset to defaults",
			appearance = "soft",
			onActivate = function()
				model.reset()
			end,
		},
	}
end
