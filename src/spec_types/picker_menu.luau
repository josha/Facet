--!strict
-- The `picker_menu` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
export type Option = {
	description: (string | coreContract.Readable<string>)?,
	enabled: (boolean | coreContract.Readable<boolean>)?,
	id: string?,
	value: any?, -- the picker shape: the identity is the value, the id names the row
	label: (string | coreContract.Readable<string>)?,
	icon: (string | coreContract.Readable<string>)?, -- semantic icon NAME, never an asset id
	divider: boolean?,
	badge: (string | number | coreContract.Readable<string | number>)?, -- the count seal
	sectionTitle: (string | coreContract.Readable<string>)?, -- a heading before this row
}
export type Spec = {
	required: boolean?,
	onChanging: ((any, any) -> boolean)?,
	enabled: any?,
	id: string?,
	options: { Option } | coreContract.Readable<{ Option }>,
	query: coreContract.Cell<string>?,
	selectedValues: coreContract.Cell<{ [string]: boolean }>?,
	placeholder: string?,
	value: (coreContract.Cell<string> | coreContract.Cell<string?>)?, -- absent for selectedValues
	--[[ THE PICKER SHAPE. `selected` is `UI.Picker`'s owner-held signal of
		an arbitrary option VALUE; `style` says which popup this is — the anchored
		`menu` or the full-sheet `navigationLink` — and its presence is what turns
		on the picker look (check-marked rows, no Cancel row in a popover, the
		picker presentation ladder). `label` puts the trigger in a FORM ROW beside
		its title; `sizing` is `hug` (the pop-up button) or `fill` (the row). ]]
	selected: any?,
	style: string?,
	label: any?,
	valueAlignment: any?, -- labeled Picker menu rows: start | end (default), or Readable
	sizing: any?,
	textSize: any?,
	-- Single selection supplies an id (nil for optional clearing); multiple
	-- selection supplies a set. Preserve callbacks narrowed to required ids.
	onChange: (((string) -> ()) | ((string?) -> ()) | (({ [string]: boolean }) -> ()))?,
	-- adaptive presentation (B-DSP3): "automatic" (default) resolves from the
	-- option count, the space class, and whether touch is a LIVE class
	presentation: string?, -- automatic | menu | inline | sheet
	sizeClass: any?, -- string | Readable<string>, e.g. adaptive.conditions().sizeClass
	interactionClasses: any?, -- table | Readable<table>, e.g. env interactionClasses
	--[[ the environment BOTH facts above come from, for a caller that would
		otherwise wire two keys to say one thing. Omitted, an automatic
		presentation finds the one this control's own core published — and refuses
		to construct if there is none. ]]
	env: any?,
}
return nil
