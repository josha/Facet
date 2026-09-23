--!strict
-- The `picker` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local statusIndicator = require("./status_indicator")
local coreContract = require("../core/contract")
export type AnyCell = coreContract.Cell<any>
export type Option = {
	id: string?,
	value: any,
	label: any,
	icon: string?,
	badge: any?,
	enabled: blueprint.Bound<boolean>?,
	description: any?,
	sectionTitle: any?,
	-- an Avatar spec (name plus optional image/userId/key/provider) leading the row
	avatar: { name: string, image: any?, userId: number?, key: string?, provider: any? }?,
	meta: any?, -- a card's (or menu row's) secondary label/value, distinct from badge
	indicator: statusIndicator.Spec?, -- a status mark in a segmented option's trailing lane
}
export type Spec<V = AnyCell> = {
	required: boolean?,
	onChanging: ((any, any) -> boolean)?,
	id: string?,
	label: blueprint.Bound<string>?,
	valueAlignment: blueprint.Bound<string>?, -- start | end (default), or Readable; labeled menu rows
	options: { Option } | coreContract.Readable<{ Option }>,
	selected: V, -- the caller's writable cell
	-- "automatic" (default) | "menu" | "segmented" | "inline" | "radioGroup" |
	-- "navigationLink" | "cards" — see the header for the ladder
	style: string?,
	presentation: string?, -- DEPRECATED alias of `style` ("radio" reads as "radioGroup")
	-- a caller-owned Signal<string>: the search text of a navigationLink list.
	-- Its presence makes the automatic style the navigation link.
	query: coreContract.Cell<string>?,
	placeholder: string?, -- the trigger's word when nothing is selected (menu styles)
	-- "automatic" (default) | "none" | "underline" | "pill" — the D4 sliding
	-- selection indicator. "automatic" is the PILL unless `presentation =
	-- "inline"` was declared, in which case it is "none" (see the header).
	indicator: string?,
	-- "x" (default) | "y" — the SEGMENTED presentation's axis, or a Readable of
	-- either. "y" is a vertical PILL (f1's left rail), which is a different shape
	-- from the `inline` row list and deliberately does not overload it. Inert
	-- under `inline`, which is a column by definition. REACTIVE because a tab
	-- bar's home moves under a live rotation and an arrangement change is a
	-- re-solve, not a rebuild (A-AL2).
	axis: blueprint.Bound<string>?,
	-- "fill" (default) | "hug", or a Readable of either. `fill` divides the offer
	-- among the segments — the shape every pre-D5 caller has; `hug` gives the band
	-- and every segment its natural width, which is what lets a strip be WIDER
	-- than its offer and therefore scroll (f1's overflowing tab strip). Inert on
	-- the vertical rail, which is content-sized by definition.
	sizing: blueprint.Bound<string>?,
	-- true makes the option ICON what every segment wears at every width, with
	-- `label` staying the semantic name (f1's icon-only pill and rail). Default
	-- false: the segment keeps its word and degrades to the glyph. A GROUP
	-- decision — see the header on why it cannot be per-option.
	iconOnly: boolean?,
	-- the TYPE ROLE every segment wears (a `TypeRole` name or a number, or a
	-- Readable of either), passed straight to each segment's Button. Nil is the
	-- Button's own default, which is what every caller before §6 had. REACTIVE for
	-- the same reason `axis` and `sizing` are: a strip's home moves under a live
	-- rotation and a tab bar in the thumb zone is caption-sized while the same
	-- strip on a rail is not.
	textSize: blueprint.Bound<number | string>?,
	sizeClass: blueprint.Bound<string>?, -- string | Readable<string> from Facet.adaptive.conditions
	env: any?, -- optional environment, so the indicator's metrics follow a live theme
	enabled: blueprint.Bound<boolean>?,
	onChange: ((value: any) -> ())?,
	-- the shared field furniture: notation in the label, one message line below
	requiredMark: ("required" | "optional")?, -- notation only; `required` stays reselect policy
	hint: blueprint.Bound<string>?,
	errorText: blueprint.Bound<string>?, -- replaces the hint and borders the menu trigger
	controlSize: blueprint.Bound<("compact" | "regular" | "large")?>?,
	-- menu: standard | contrast | utility; segmented: filled | stroke | utility;
	-- automatic takes all five and maps them onto the family on screen
	appearance: blueprint.Bound<string?>?,
	corners: ("pill" | "square")?,
	maxHeight: number?, -- the menu panel's bound in px, chrome included
	indicatorPosition: ("leading" | "trailing")?, -- radioGroup: the mark's edge
}
export type StyleFacts = {
	optionCount: number,
	longestLabel: number,
	sizeClass: string?,
	distanceProfile: string?, -- "near" | "ten-foot"
	primaryInput: string?, -- "touch" | "pointer" | "gamepad"
	searchable: boolean?,
	hasDescription: boolean?, -- any option carries a description (a row, never a segment)
	fits: boolean?, -- the estimated segmented band fits the offer at the current text size (nil = unknown)
}
return nil
