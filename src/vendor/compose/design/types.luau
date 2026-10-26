--!strict

local Core = require "../core"

type ReadOnlyValue<T> = Core.Value<T>

export type Literal = string | number | boolean | { [string | number]: Literal }

export type Value = {
	literal: Literal?,
	input: string?,
	item: string?,
	output: string?,
	args: { Literal }?,
	token: string?,
}

export type FieldType = "string" | "number" | "boolean" | "choice" | "color" | "vector3" | "value" | "event" | "content"

export type Field = {
	type: FieldType,
	options: { string }?,
	tokens: boolean?,
	group: string?,
	order: number?,
	default: Literal?,
}

export type Row = { [string | number]: Literal }

export type Resolved = {
	literal: Literal?,
	readable: ReadOnlyValue<Literal?>?,
	callback: ((...Literal) -> ())?,
	template: ((row: ReadOnlyValue<Row>) -> unknown)?,
	slot: (() -> unknown)?,
	rows: ReadOnlyValue<{ Row }>?,
	key: string?,
}

export type Children = "none" | "list" | "template" | "slot"

export type Kind = {
	fields: { [string]: Field },
	defaults: { [string]: Literal }?,
	children: Children,
	template: string?,
	slot: string?,
	category: string?,
	source: string?,
	key: string?,
	call: string,
	build: (props: { [string]: Resolved }, children: { unknown }) -> unknown,
}

export type Library = {
	name: string,
	parameter: string,
	parameterType: string,
	prelude: { string },
	returnType: string,
	readable: string,
	cell: string,
	token: string?,
	space: ("2d" | "3d")?,
	kinds: { [string]: Kind },
}

export type InputKind = "value" | "readable" | "cell"
export type InputType = "string" | "number" | "boolean" | "color" | "image" | "list" | "record" | "slot"

export type ItemField = { id: string, type: InputType }

export type Input = {
	id: string,
	kind: InputKind,
	type: InputType,
	preview: Literal?,
	fields: { ItemField }?,
}

export type Output = { id: string }

export type Contract = { inputs: { Input }, outputs: { Output } }

export type Bind = { from: string, key: string }

export type Node = {
	id: string,
	kind: string,
	name: string,
	props: { [string]: Value },
	children: { Node },
	bind: Bind?,
}

export type Document = {
	schema: "compose-design/1",
	name: string,
	library: string,
	nextId: number,
	contract: Contract,
	root: Node,
}

return {}
