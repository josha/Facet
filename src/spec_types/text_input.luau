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
	-- Enter / focus loss / submit. The number presentation reports the committed
	-- NUMBER, and "clamped" when a bound moved it; the others report the string.
	onCommit: ((value: string | number, reason: "enter" | "focusLost" | "submit" | "clamped") -> ())?,
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
	-- the shared field chrome
	label: blueprint.Bound<string>?, -- the words above the field; a tap focuses it
	requiredMark: ("required" | "optional")?, -- notation only; it never validates
	hint: blueprint.Bound<string>?, -- the line under the field at rest
	errorText: blueprint.Bound<string>?, -- non-empty replaces the hint; shakes nothing
	leading: any?, -- a static blueprint inside the plate, before the editor
	trailing: any?, -- a blueprint inside the plate, after the clear affordance
	controlSize: blueprint.Bound<("xsmall" | "compact" | "regular" | "large")?>?,
	appearance: blueprint.Bound<("standard" | "contrast" | "utility")?>?,
	corners: ("pill" | "square")?,
	-- focusable, selectable and full contrast, accepting no edit; not `enabled = false`
	readOnly: blueprint.Bound<boolean>?,
	-- what each new focus session selects; the default keeps the native caret
	selectOnFocus: blueprint.Bound<("none" | "all" | "end")?>?,
	-- multiline only: lines shown at once; past them the editor scrolls
	visibleLines: number?,
	-- the number presentation
	step: number?, -- finite and above zero; one press of a step button
	precision: number?, -- 0..10 decimal places, rounded half away from zero at commit
	stepButtons: boolean?, -- two target-sized stops in the plate
	prefix: blueprint.Bound<string>?, -- unit chrome beside the editor, never in the draft
	suffix: blueprint.Bound<string>?,
	-- a horizontal drag across the editor moves the number by steps
	scrub: blueprint.Bound<boolean>?,
}
-- `UI.NumberInput`: the number presentation preset; it chooses the presentation
export type NumberSpec<V = StringCell> = Spec<V> & {
	presentation: nil,
	numericValue: coreContract.Cell<number>,
}
return nil
