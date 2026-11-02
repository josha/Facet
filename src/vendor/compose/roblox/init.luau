--!strict

local Compose = require "./core"
local Engine = require "@self/engine"
local HostImpl = require "@self/host"
local Codecs = require "@self/codecs"

export type Codecs = Codecs.Codecs
export type CodecSource = Codecs.Source
export type Engine = Engine.Engine
export type Signal<A... = ...unknown> = Engine.Signal<A...>
export type Connection = Engine.Connection
export type Viewport = Engine.Viewport
export type ViewportOptions = Engine.ViewportOptions
export type PreferredInputClass = Engine.PreferredInputClass
export type PreferredInputSpec = Engine.PreferredInputSpec

local sharedHost: Compose.Host? = nil

local function createHost(engine: Engine.Engine?): Compose.Host
	if engine ~= nil then
		local host = HostImpl.createHost(engine)
		return host
	end

	local existing = sharedHost
	if existing ~= nil then
		return existing
	end
	local ambient = Engine.ambient()
	local host = HostImpl.createHost(ambient)
	sharedHost = host
	return host
end

local function createRuntime(engine: Engine.Engine?): Compose.Runtime
	return Compose.createRuntime(createHost(engine))
end

local function designEnvironment(options: {
	values: typeof(Engine.designEnvironment(HostImpl.readMember).values),
	service: (string) -> unknown,
	read: ((unknown, string) -> unknown)?,
}?): typeof(Engine.designEnvironment(HostImpl.readMember))
	if options then
		local read = options.read or HostImpl.readMember
		return {
			read = read,
			values = options.values,
			service = options.service,
			descendants = Engine.descendants,
			invoke = function(object: unknown, method: string, ...: unknown): ...unknown
				return Engine.invoke(read, object, method, ...)
			end,
		}
	end
	return Engine.designEnvironment(HostImpl.readMember)
end

local function codecs(engine: CodecSource?): Codecs
	return Codecs.create(if engine ~= nil then engine else Engine.ambient())
end

local function animatableTypes(engine: Engine.Engine?): { string }
	local supplied = codecs(engine)
	local names: { string } = {}
	if supplied.CFrame ~= nil then
		table.insert(names, "CFrame")
	end
	if supplied.Color3 ~= nil then
		table.insert(names, "Color3")
	end
	if supplied.UDim ~= nil then
		table.insert(names, "UDim")
	end
	if supplied.UDim2 ~= nil then
		table.insert(names, "UDim2")
	end
	if supplied.Vector2 ~= nil then
		table.insert(names, "Vector2")
	end
	if supplied.Vector3 ~= nil then
		table.insert(names, "Vector3")
	end
	table.sort(names)
	return names
end

local cleanupModule: typeof(require "@self/cleanup")? = nil
local function cleanupOf(): typeof(require "@self/cleanup")
	local loaded = cleanupModule
	if loaded ~= nil then
		return loaded
	end
	local required = require "@self/cleanup"
	cleanupModule = required
	return required
end

local viewportModule: typeof(require "@self/viewport")? = nil
local function viewportOf(): typeof(require "@self/viewport")
	local loaded = viewportModule
	if loaded ~= nil then
		return loaded
	end
	local required = require "@self/viewport"
	viewportModule = required
	return required
end

local inputModule: typeof(require "@self/input")? = nil
local function inputOf(): typeof(require "@self/input")
	local loaded = inputModule
	if loaded ~= nil then
		return loaded
	end
	local required = require "@self/input"
	inputModule = required
	return required
end

local function cleanup(value: unknown): Compose.Dispose
	return cleanupOf().cleanup(value)
end

local function createCleanup(typeName: ((value: unknown) -> string)?): (value: unknown) -> Compose.Dispose
	return cleanupOf().createCleanup(typeName)
end

local function createViewport(
	camera: unknown,
	engine: Engine.Engine?,
	options: Engine.ViewportOptions?
): (Compose.ReadOnlyValue<Engine.Viewport>, Compose.ReadOnlyValue<boolean>)
	return viewportOf().createViewport(camera, engine, options)
end

local function usableViewportSize(size: Engine.Vector2?, minimum: number?): boolean
	return viewportOf().usableViewportSize(size, minimum)
end

local function preferredInput(inputService: unknown, engine: Engine.Engine?): Compose.Value<Engine.PreferredInputClass>
	return inputOf().preferredInput(inputService, engine)
end

local function preferredInputSpec(value: unknown): Engine.PreferredInputSpec
	return inputOf().preferredInputSpec(value)
end

local function __resetForTests()
	sharedHost = nil
end

return {
	createHost = createHost,
	createRuntime = createRuntime,
	designEnvironment = designEnvironment,
	codecs = codecs,
	animatableTypes = animatableTypes,
	cleanup = cleanup,
	createCleanup = createCleanup,
	createViewport = createViewport,
	usableViewportSize = usableViewportSize,
	preferredInput = preferredInput,
	preferredInputSpec = preferredInputSpec,
	__resetForTests = __resetForTests,
}
