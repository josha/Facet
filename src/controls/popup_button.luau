--!strict
--[[ DEPRECATED SURFACE (2026-09-11; `Facet.DEPRECATIONS`, since 0.11.0,
	removeNoEarlierThan 0.12.0). `UI.PopupButton` was
	the popup half of what `UI.Picker` now owns as `style = "menu"` and
	`style = "navigationLink"`. Its whole body moved to
	`src/controls/picker_menu.luau`, which both surfaces run on; this module is
	the name the old callers required, kept working for the deprecation window
	and nothing more. New callers write `UI.Picker(core, { style = ... })`.
	`resolvePresentation` stays an alias of `menu_recipe.resolvePresentation`,
	exactly as it was before the move. ]]

local pickerMenu = require("./picker_menu")

export type Option = pickerMenu.Option
export type Spec = pickerMenu.Spec

local popup_button = {}
popup_button.build = pickerMenu.build
popup_button.resolvePresentation = pickerMenu.resolvePresentation
return popup_button
