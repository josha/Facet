--!strict

local Core = require("../vendor/compose/core")
local Design = require("../vendor/compose/design/types")
local Library = require("../vendor/compose/design/library")
local Engine = require("../ui/engine_types")
local ControlTypes = require("../ui/control_types")
local ThemeTypes = require("../ui/theme_types")

export type Literal = Design.Literal
export type Extension = Library.Extension
export type RobloxTypes = Engine.RobloxTypes

export type FieldSpec = {
	type: Design.FieldType,
	label: string,
	order: number,
	options: { string }?,
	format: string?,
	default: Literal?,
	perRow: boolean?,
	tokens: boolean?,
}

export type DerivedField = { type: Design.FieldType, options: { string }?, datatype: string?, also: { string }? }

export type DerivedKind = { children: boolean, fields: { [string]: DerivedField } }

export type Derived = { controls: { [string]: DerivedKind }, host: { [string]: DerivedKind } }

export type Seed = { kind: string, props: { [string]: Literal }?, children: { Seed }? }

export type RegisteredDesign = {
	contract: Design.Contract,
	call: string,
	prelude: { string }?,
	category: string?,
	build: (UI: unknown, props: { [string]: unknown }, name: string) -> unknown,
}

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
	space: ("2d" | "3d")?,
	types: RobloxTypes?,
	host: ((className: string, name: string, props: { [unknown]: unknown }) -> unknown)?,
	provide: ((content: unknown) -> unknown)?,
	tokens: Tokens?,
	motion: Motion?,
	extension: Library.Extension?,
	designs: { [string]: RegisteredDesign }?,
}

export type Motion = {
	animate: (source: Core.ReadOnlyValue<Literal?>, role: string) -> Core.ReadOnlyValue<Literal?>,
	sequence: (
		sequence: Design.Sequence,
		states: { [string]: Core.Value<Literal?> },
		outputs: { [string]: () -> () }
	) -> Design.Player,
}

export type Tokens = {
	path: string,
	require: string,
}

export type StudioEditor = typeof(require("../vendor/compose/design-editor").create(
	nil :: never,
	nil :: never,
	nil :: never,
	nil :: never
))
export type StudioStage = typeof(require("../vendor/compose/design-editor/devices").get(""))
export type StudioFrame = typeof(((nil :: unknown) :: StudioEditor).canvas.current())
export type StudioResult = typeof(((nil :: unknown) :: StudioEditor).execute({ action = "Read" }))
export type StudioSampleBindings = (UI: ControlTypes.Controls, stage: StudioStage) -> { [string]: Design.Resolved }
export type StudioSample = {
	design: string,
	name: string,
	props: { [string]: Literal },
	bindings: StudioSampleBindings?,
}
export type StudioOptions = {
	registry: { [string]: RegisteredDesign },
	samples: { StudioSample },
	stages: { StudioStage }?,
	resolution: { X: number, Y: number }?,
	theme: ThemeTypes.ReadOnlyThemePackage?,
	themes: { string }?,
	textSizes: { string }?,
	capture: ((name: string, frame: StudioFrame) -> { string })?,
}
export type StudioKit = {
	name: string,
	edit: (parent: unknown, name: string, link: Design.LinkStore?) -> StudioEditor,
}

return {}
