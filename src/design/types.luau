--!strict

local Design = require("../vendor/compose/design/types")

export type Literal = Design.Literal

export type FieldSpec = {
	type: Design.FieldType,
	label: string,
	order: number,
	options: { string }?,
	format: string?,
}

export type DerivedField = { type: Design.FieldType, options: { string }?, datatype: string? }

export type DerivedKind = { children: boolean, fields: { [string]: DerivedField } }

export type Derived = { controls: { [string]: DerivedKind }, host: { [string]: DerivedKind } }

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

export type Context = {
	UI: unknown,
	rgb: (r: number, g: number, b: number) -> unknown,
	udim2: (xScale: number, xOffset: number, yScale: number, yOffset: number) -> unknown,
	offset: (x: number, y: number) -> unknown,
	datatype: ((name: string, components: { number }) -> unknown)?,
	enumItem: ((enumName: string, item: string) -> unknown)?,
	host: ((className: string, name: string, props: { [unknown]: unknown }) -> unknown)?,
}

return {}
