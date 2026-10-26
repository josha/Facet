--!strict

local Core = require "../core"

type ReadOnlyValue<T> = Core.ReadOnlyValue<T>

export type Literal = string | number | boolean | { [string | number]: Literal }

export type Value = {
	literal: Literal?,
	input: string?,
	item: string?,
	output: string?,
	args: { Literal }?,
	fields: { string }?,
	node: string?,
	nodeFrom: string?,
	nodes: { string }?,
	token: string?,
	state: string?,
	motion: string?,
	play: string?,
}

export type FieldType =
	"string"
	| "number"
	| "boolean"
	| "choice"
	| "color"
	| "vector3"
	| "value"
	| "event"
	| "content"
	| "node"
	| "datatype"

export type Field = {
	type: FieldType,
	options: { string }?,
	tokens: boolean?,
	group: string?,
	order: number?,
	default: Literal?,
	datatype: string?,
	also: { string }?,
	luauType: string?,
	label: string?,
	advanced: boolean?,
	requires: { [string]: { Literal } }?,
	perRow: boolean?,
}

export type Row = { [string | number]: Literal }

export type Resolved = {
	literal: Literal?,
	value: unknown,
	readable: ReadOnlyValue<Literal?>?,
	callback: ((...Literal) -> ())?,
	template: ((row: ReadOnlyValue<Row>) -> unknown)?,
	slot: (() -> unknown)?,
	rows: ReadOnlyValue<{ Row }>?,
	node: ReadOnlyValue<unknown>?,
	key: string?,
}

export type Children = "none" | "list" | "template" | "slot"

export type Seed = { kind: string, props: { [string]: Literal }?, children: { Seed }? }

export type Kind = {
	fields: { [string]: Field },
	defaults: { [string]: Literal }?,
	seeds: { Seed }?,
	children: Children,
	leaf: boolean?,
	template: string?,
	slot: string?,
	category: string?,
	source: string?,
	key: string?,
	call: string,
	build: (props: { [string]: Resolved }, children: { unknown }, name: string) -> unknown,
}

export type Motion = {
	call: string,
	roles: { string },
	animate: ((source: ReadOnlyValue<Literal?>, role: string) -> ReadOnlyValue<Literal?>)?,
}

export type SequenceStep = {
	delay: string?,
	duration: string?,
	easing: string?,
	state: string?,
	to: Literal?,
	output: string?,
}

export type Sequence = { id: string, autoplay: boolean?, steps: { SequenceStep } }

export type Player = { play: () -> () }

export type Sequencing = {
	call: string,
	toward: string,
	build: (
		(sequence: Sequence, states: { [string]: Core.Value<Literal?> }, outputs: { [string]: () -> () }) -> Player
	)?,
}

export type Library = {
	name: string,
	parameter: string,
	parameterType: string,
	prelude: { string },
	returnType: string,
	readable: string,
	cell: string,
	newCell: string?,
	token: string?,
	show: string?,
	keyed: string?,
	categories: { string }?,
	contentKind: string?,
	tags: { call: string, apply: (built: unknown, tags: { string }) -> () }?,
	space: ("2d" | "3d")?,
	provide: ((content: unknown) -> unknown)?,
	motion: Motion?,
	sequence: Sequencing?,
	kinds: { [string]: Kind },
}

export type InputKind = "value" | "readable" | "cell"
export type InputType = "string" | "number" | "boolean" | "color" | "image" | "list" | "record" | "slot"

export type ItemField = { id: string, type: InputType, fields: { ItemField }?, luauType: string? }

export type Input = {
	id: string,
	kind: InputKind,
	type: InputType,
	preview: Literal?,
	fields: { ItemField }?,
	required: boolean?,
	luauType: string?,
}

export type Output = { id: string, args: { InputType }?, row: string? }

export type State = { id: string, type: InputType, initial: Literal }

export type Contract = { inputs: { Input }, outputs: { Output } }

export type Bind = { from: string, key: string, row: string? }

export type Node = {
	id: string,
	kind: string,
	name: string,
	props: { [string]: Value },
	children: { Node },
	bind: Bind?,
	nameField: string?,
	nameInput: string?,
	when: string?,
	tags: { string }?,
}

export type Document = {
	schema: "compose-design/1",
	name: string,
	library: string,
	nextId: number,
	contract: Contract,
	state: { State }?,
	sequences: { Sequence }?,
	root: Node,
}

export type EmitOptions = {
	name: string?,
	rowFunctions: boolean?,
	localControls: boolean?,
	controls: string?,
	propsType: string?,
	prelude: { string }?,
}

export type RenderContext = {
	inputs: { [string]: Literal }?,
	bindings: { [string]: Resolved }?,
	outputs: { [string]: (args: { Literal }) -> () }?,
	slots: { [string]: () -> unknown }?,
	token: ((name: string) -> Literal)?,
	resolveToken: ((name: string) -> Resolved)?,
	decorate: ((node: Node, built: unknown) -> ())?,
	players: ((players: { [string]: Player }) -> ())?,
}

export type LinkStore = {
	read: () -> string,
	write: (expected: string, generated: string) -> boolean,
	watch: (changed: () -> ()) -> () -> (),
}

export type OpenDesign = { dispose: () -> () }

export type Kit = {
	name: string,
	edit: (parent: unknown, name: string, link: LinkStore?) -> OpenDesign,
}

return {}
