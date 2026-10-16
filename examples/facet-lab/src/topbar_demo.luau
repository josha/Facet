--!strict
type Context = {
	UI: typeof(require("@repo/tools/typecheck/aliases").FacetControls),
	cell: typeof(require("@repo/tools/typecheck/aliases").CellFactory),
}

return function(c: Context): Instance
	local UI = c.UI
	local open = c.cell("stripSettingsOpen", false)
	return UI.Region "StripSettings" {
		zone = "topbar",
		rank = 1,
		leading = true,
		UI.Popover "StripSettingsPopover" {
			title = "Strip settings",
			isPresented = open,
			onPresentedChange = function(value: boolean)
				open:set(value)
			end,
			compact = "popover",
			modal = false,
			closeButton = true,
			trigger = UI.Button "StripSettingsButton" {
				name = "Strip settings",
				icon = "settings",
				shape = "circle",
				controlSize = "compact",
			},
			content = function(): Instance
				return UI.Text {
					text = "This popup uses the screen outside the top-bar strip.",
					wrap = true,
					Size = UDim2.fromOffset(220, 0),
					AutomaticSize = Enum.AutomaticSize.Y,
				}
			end,
		},
	}
end
