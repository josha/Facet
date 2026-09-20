--!strict
-- The `text_input` control's types, apart from its implementation: reading a type must
-- not load the control.
local blueprint = require("../blueprint")
local coreContract = require("../core/contract")
export type StringCell = coreContract.Cell<string>
export type Spec<V = StringCell> = {
	presentation: ("plain" | "search" | "number")?,
	numericValue: coreContract.Cell<number>?,
	min: number?,
	max: number?,
	parse: ((string) -> number?)?,
	format: ((number) -> string)?,
	multiline: boolean?,
	height: blueprint.Bound<blueprint.Dim>?,
	onCancel: (() -> ())?,
	enabled: (boolean | coreContract.Readable<boolean>)?,
	id: string?,
	value: V, -- the caller's writable cell of the field text
	onChange: ((text: string) -> ())?, -- live: every accepted edit while typing
	onCommit: ((text: string, reason: "enter" | "focusLost" | "submit") -> ())?, -- Enter / focus loss
	placeholder: string?,
	disabled: blueprint.Bound<boolean>?, -- boolean | Readable<boolean>
	keyboardType: ("default" | "numeric" | "email" | "phone")?,
	submitLabel: ("default" | "done" | "go" | "next" | "search" | "send")?,
	clearButton: boolean?, -- trailing × affordance; sugar for clearButtonMode = "always"
	clearButtonMode: ("never" | "whileEditing" | "unlessEditing" | "always")?,
	maxLength: number?, -- accepted text clamped at the value-model boundary
	validate: ((proposed: string) -> string?)?, -- accept(normalized) | nil=reject
	invalid: coreContract.Readable<boolean>?,
	env: any?, -- Environment: enables keyboard-occlusion keep-visible
	actionSystem: any?, -- injected: enables the text-entry sinking context
}
return nil
