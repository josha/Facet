--!strict

local Design = require("../vendor/compose/design")

export type Literal = Design.Literal

export type FieldSpec = {
	type: Design.FieldType,
	label: string,
	order: number,
	options: { string }?,
	format: string?,
}

export type Seed = { kind: string, props: { [string]: Literal }?, children: { Seed }? }

export type ControlSpec = {
	category: string,
	defaults: { [string]: Literal },
	fields: { [string]: FieldSpec },
	container: boolean?,
	content: string?,
	state: string?,
	states: { string }?,
	anchor: string?,
	nativeSize: boolean?,
	seeds: { Seed }?,
}

return {}
