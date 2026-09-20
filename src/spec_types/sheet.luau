--!strict
-- The `sheet` control's types, apart from its implementation: reading a type must
-- not load the control.
local publicCore = require("../core/contract")
local publicBlueprint = require("../blueprint")
local publicEnv = require("../env/environment")
export type StringCell = publicCore.Cell<string>
export type BooleanCell = publicCore.Cell<boolean>
export type Spec<V = StringCell, P = BooleanCell> = {
	id: string?,
	title: publicBlueprint.Bound<string>,
	content: publicBlueprint.Blueprint | (() -> publicBlueprint.Blueprint),
	detent: V,
	detents: { "medium" | "large" | { id: string, fraction: number?, height: number? } }?,
	env: publicEnv.Env?,
	presenter: any?,
	isPresented: P?,
	interactiveDismissDisabled: boolean?,
	dragIndicator: ("automatic" | "visible" | "hidden")?,
}
return nil
