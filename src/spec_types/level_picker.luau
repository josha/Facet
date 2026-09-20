--!strict
-- The `level_picker` control's types, apart from its implementation: reading a type must
-- not load the control.
local coreContract = require("../core/contract")
local blueprint = require("../blueprint")
export type NumberCell = coreContract.Cell<number>
export type Spec<V = NumberCell> = {
	id: string?,
	value: V, -- the caller's writable cell of a number
	count: number?, -- how many levels; default 5
	allowZero: boolean?,
	segment: ("bar" | "glyph" | "image")?,
	glyphs: { filled: string, empty: string }?,
	images: { filled: string, empty: string }?,
	tint: { filled: any?, empty: any? }?,
	enabled: blueprint.Bound<boolean>?, -- boolean | Readable<boolean>
	readOnly: boolean?,
	segmentSize: ("small" | "medium" | "large")?,
	env: any?,
	onChange: ((value: number) -> ())?,
}
export type Config = {
	constructor: string,
	names: { run: string, mark: string },
	id: string,
	value: V,
	count: number,
	minValue: number,
	segment: string,
	sizeRole: string,
	glyphs: { filled: string, empty: string }?,
	images: { filled: string, empty: string }?,
	tint: { filled: any?, empty: any? },
	targetFloor: boolean,
	readOnly: boolean,
	enabled: blueprint.Bound<boolean>?,
	env: any?,
	onChange: ((value: number) -> ())?,
	diagnostics: { string },
}
return nil
