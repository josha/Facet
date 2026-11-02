--!strict
--!nolint DeprecatedApi
local Dynamic = require "../core/dynamic"

local Types = require "./types"

export type Viewport = Types.Viewport
export type ViewportOptions = Types.ViewportOptions
export type PreferredInputClass = Types.PreferredInputClass
export type PreferredInputSpec = Types.PreferredInputSpec
export type Connection = Types.Connection
export type Destroyable = Types.Destroyable
export type Signal<A... = ...unknown> = Types.Signal<A...>
export type Vector2 = Types.Vector2
export type Vector3 = Types.Vector3
export type Color3 = Types.Color3
export type UDim = Types.UDim
export type UDim2 = Types.UDim2
export type CFrame = Types.CFrame
export type Instance = Types.Instance
export type DataModel = Types.DataModel
export type Datatypes = Types.Datatypes
export type Engine = Types.Engine
export type Codecs = Types.Codecs
export type Source = Types.Source

local ambientModule: typeof(require "./ambient")? = nil

local function ambient(): Engine
	local loaded = ambientModule or require "./ambient"
	ambientModule = loaded
	return loaded.ambient()
end

local function designEnvironment(read: (unknown, string) -> unknown)
	local loaded = ambientModule or require "./ambient"
	ambientModule = loaded
	return loaded.designEnvironment(read)
end

local function descendants(object: unknown): { unknown }
	local loaded = ambientModule or require "./ambient"
	ambientModule = loaded
	return loaded.descendants(object)
end

local function service(name: string): unknown
	local loaded = ambientModule or require "./ambient"
	ambientModule = loaded
	return loaded.service(name)
end

local function cancelThread(thread: thread): boolean
	local loaded = ambientModule or require "./ambient"
	ambientModule = loaded
	return loaded.cancelThread(thread)
end

local function invoke(read: (unknown, string) -> unknown, object: unknown, method: string, ...: unknown): ...unknown
	return Dynamic.invoke(read(object, method), object, ...)
end

return {
	ambient = ambient,
	designEnvironment = designEnvironment,
	descendants = descendants,
	invoke = invoke,
	readMember = Dynamic.read,
	writeMember = Dynamic.write,
	service = service,
	cancelThread = cancelThread,
}
