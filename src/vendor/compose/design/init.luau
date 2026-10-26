--!strict

local Document = require "@self/document"
local History = require "@self/history"
local Library = require "@self/library"
local Link = require "@self/link"
local Render = require "@self/render"
local Session = require "@self/session"
local Source = require "@self/source"
local Types = require "@self/types"

export type Literal = Types.Literal
export type Value = Types.Value
export type Field = Types.Field
export type FieldType = Types.FieldType
export type Kind = Types.Kind
export type Library = Types.Library
export type Input = Types.Input
export type Output = Types.Output
export type Contract = Types.Contract
export type Bind = Types.Bind
export type State = Types.State
export type InputType = Types.InputType
export type ItemField = Types.ItemField
export type Resolved = Types.Resolved
export type Row = Types.Row
export type Node = Types.Node
export type Document = Types.Document
export type History = History.History
export type Extension = Library.Extension
export type EmitOptions = Source.EmitOptions
export type RenderContext = Render.Context
export type Session = Session.Session
export type Link = Link.Link
export type LinkStore = Link.Store
export type LinkStatus = Link.Status

return {
	document = Document,
	history = History,
	render = Render,
	session = Session,
	link = Link,
	extend = Library.extend,
	emit = Source.emit,
	parse = Source.parse,
}
