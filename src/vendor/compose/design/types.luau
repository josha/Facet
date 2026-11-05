--!strict

local Core = require "../core"

type ReadOnlyValue<T> = Core.ReadOnlyValue<T>

export type Literal = string | number | boolean | { [string | number]: Literal }
export type DatatypeComponent = number | { token: string } | { input: string }
export type ActionArgument = { item: string, event: nil } | { item: nil, event: number }

export type Value = {
	literal: Literal?,
	input: string?,
	path: { string }?,
	item: string?,
	output: string?,
	args: { Literal }?,
	fields: { string }?,
	arguments: { ActionArgument }?,
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
	reference: ("readable" | "native")?,
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
	design: ImportedDesign?,
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
	staticRows: boolean?,
	iteration: { fields: { ItemField } }?,
	call: string,
	build: (props: { [string]: Resolved }, children: { unknown }, name: string) -> unknown,
	selectionTarget: ((built: unknown, use: Core.Use) -> unknown)?,
}

export type Motion = {
	call: string,
	roles: { string },
	animate: ((source: ReadOnlyValue<Literal?>, role: string) -> ReadOnlyValue<Literal?>)?,
}

export type ImportedDesign = {
	source: ReadOnlyValue<string>,
	library: Library,
	nameInput: string,
	contract: Contract,
	save: ((expected: string, generated: string) -> boolean)?,
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
	rowReadable: string?,
	cell: string,
	newCell: string?,
	token: string?,
	show: string?,
	keyed: string?,
	categories: { string }?,
	contentKind: string?,
	containerKind: string?,
	tags: { call: string, apply: (built: unknown, tags: { string }) -> () }?,
	space: ("2d" | "3d")?,
	provide: ((content: unknown) -> unknown)?,
	motion: Motion?,
	sequence: Sequencing?,
	kinds: { [string]: Kind },
}

export type InputKind = "value" | "readable" | "cell"
export type InputType = "string" | "number" | "boolean" | "color" | "image" | "vector3" | "list" | "record" | "slot"

export type ItemField = { id: string, type: InputType, fields: { ItemField }?, luauType: string?, options: { string }? }

export type Input = {
	id: string,
	kind: InputKind,
	type: InputType,
	preview: Literal?,
	fields: { ItemField }?,
	required: boolean?,
	luauType: string?,
	options: { string }?,
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
	hidden: boolean?,
	locked: boolean?,
	rowVariant: RowVariant?,
	tagBinding: Value?,
	slot: string?,
}

export type VariantCase = { value: string, kind: string, props: { [string]: Value }, children: { Node } }
export type RowVariant = { item: string, cases: { VariantCase } }

export type Document = {
	schema: "compose-design/1",
	name: string,
	library: string,
	nextId: number,
	contract: Contract,
	typeImports: { string }?,
	state: { State }?,
	sequences: { Sequence }?,
	root: Node,
	rootVariant: RootVariant?,
}

export type RootVariant = {
	input: string,
	value: string,
	kind: string,
	props: { [string]: Value },
	children: { Node }?,
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
	use: Core.Use?,
	inputs: { [string]: Literal }?,
	bindings: { [string]: Resolved }?,
	outputs: { [string]: (args: { Literal }) -> () }?,
	slots: { [string]: () -> unknown }?,
	token: ((name: string) -> Literal)?,
	resolveToken: ((name: string) -> Resolved)?,
	decorate: ((node: Node, built: unknown) -> ())?,
	exclude: ((node: Node) -> boolean)?,
	players: ((players: { [string]: Player }) -> ())?,
}

export type LinkStore = {
	read: () -> string,
	write: (expected: string, generated: string) -> boolean,
	watch: (changed: () -> ()) -> () -> (),
	read defer: ((save: () -> ()) -> ())?,
}

export type OpenDesign = { dispose: () -> () }

export type Kit = {
	name: string,
	edit: (parent: unknown, name: string, link: LinkStore?) -> OpenDesign,
}

return {}
