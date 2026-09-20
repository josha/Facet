--!strict
-- The `alert` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
export type Text = string | coreContract.Readable<string>
export type Action = {
	id: string,
	label: Text,
	compactLabel: Text?,
	role: ("default" | "cancel" | "destructive")?,
	enabled: (boolean | coreContract.Readable<boolean>)?,
	shortcut: ("defaultAction" | "cancelAction" | { keyCode: string, modifiers: { shift: boolean? }? })?,
	onActivate: ((any?) -> ())?,
}
export type BooleanCell = coreContract.Cell<boolean>
export type Spec<P = BooleanCell> = {
	id: string?,
	title: (Text | ((any) -> Text))?,
	message: (Text | ((any) -> Text))?,
	actions: ({ Action } | ((any) -> { Action }))?,
	isPresented: P?,
	presenter: any?,
	presenting: any?,
	item: coreContract.Cell<any>?,
	error: any?,
	icon: Text?,
	severity: ("automatic" | "standard" | "critical")?,
	suppression: { isSuppressed: coreContract.Cell<boolean>, label: Text? }?,
	content: ((any, any?) -> any)?,
	env: any?,
	maxWidth: (number | string)?,
	padding: (number | string)?,
	surface: string?,
	-- the modal's own enter/exit (transitions round 2026-09-12); default is the
	-- materialize fade-and-grow, and `{ enter = "instant" }` opts out
	transition: any?,
}
return nil
