--!strict

local Facet = require(game:GetService("ReplicatedStorage").Facet)

export type Props = {
	open: Facet.Value<boolean>,
	path: Facet.Value<Facet.NavigationPath>,
	music: Facet.Value<boolean>,
	volume: Facet.Value<number>,
	onDetails: ((...unknown) -> ())?,
	onPresentedChange: ((boolean) -> ())?,
}

local _design = {
	contract = {
		inputs = {
			{ id = "open", kind = "cell", preview = true, required = true, type = "boolean" },
			{
				id = "path",
				kind = "cell",
				luauType = "Facet.NavigationPath",
				preview = {},
				required = true,
				type = "record",
			},
			{ id = "music", kind = "cell", preview = true, required = true, type = "boolean" },
			{ id = "volume", kind = "cell", preview = 50, required = true, type = "number" },
		},
		outputs = { { id = "onDetails" }, { args = { "boolean" }, id = "onPresentedChange" } },
	},
	name = "NavigableDialog",
}

local function NavigableDialog(UI: Facet.Controls, props: Props): GuiObject
	return UI.Dialog "Preferences" {
		bodyHeight = 420,
		closeButton = true,
		isPresented = props.open,
		onPresentedChange = function(event1: boolean)
			if props.onPresentedChange then
				props.onPresentedChange(event1)
			end
		end,
		presentation = "inset",
		title = "Preferences",
		content = function()
			return UI.NavigationStack "PreferencesNavigation" {
				destinations = {
					details = {
						content = function()
							return UI.ScrollView "DisplayDetails" {
								gap = "m",
								height = "fill",
								width = "fill",
								UI.Text "DisplayHelp" {
									text = "Text and controls follow the display resolution and viewing distance. Long content scrolls inside this dialog.",
									wrap = true,
								},
							}
						end,
						title = "Display details",
					},
				},
				path = props.path,
				root = {
					content = function()
						return UI.ScrollView "PreferencesForm" {
							gap = "m",
							height = "fill",
							width = "fill",
							UI.Text "Introduction" {
								text = "Choose how the interface sounds and displays information.",
								wrap = true,
							},
							UI.Toggle "Music" {
								label = "Music",
								value = props.music,
							},
							UI.Slider "Volume" {
								label = "Volume",
								max = 100,
								min = 0,
								value = props.volume,
							},
							UI.Text "AudioHelp" {
								text = "Volume changes apply while this form is open. Your draft remains available when you open details or rotate the screen.",
								wrap = true,
							},
							UI.Button "Details" {
								label = "Display details",
								onActivate = function(...)
									if props.onDetails then
										props.onDetails(...)
									end
								end,
							},
							UI.Text "ReturnHelp" {
								text = "Use Back to return from details. Close returns to the previous task.",
								wrap = true,
							},
						}
					end,
				},
			}
		end,
	}
end

return NavigableDialog
