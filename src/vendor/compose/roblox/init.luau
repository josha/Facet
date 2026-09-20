--!strict

local Cleanup = require "@self/cleanup"
local Codecs = require "@self/codecs"
local Compose = require "./core"
local Engine = require "@self/engine"
local HostImpl = require "@self/host"
local Input = require "@self/input"
local PreferredInput = require "@self/preferred-input"
local Viewport = require "@self/viewport"

export type Engine = Engine.Engine
export type Signal = Engine.Signal
export type Connection = Engine.Connection
export type Viewport = Viewport.Viewport
export type ViewportOptions = Viewport.Options
export type PreferredInputClass = PreferredInput.Class
export type PreferredInputSpec = PreferredInput.Spec

local sharedHost: Compose.Host? = nil

local function createHost(engine: Engine.Engine?): Compose.Host
	if engine ~= nil then
		local host = HostImpl.createHost(engine)
		Codecs.register(engine)
		return host
	end

	local existing = sharedHost
	if existing ~= nil then
		return existing
	end
	local ambient = Engine.ambient()
	local host = HostImpl.createHost(ambient)
	Codecs.register(ambient)
	sharedHost = host
	return host
end

local function createRuntime(engine: Engine.Engine?): Compose.Runtime
	return Compose.createRuntime(createHost(engine))
end

local function animatableTypes(engine: Engine.Engine?): { string }
	local resolved = if engine ~= nil then engine else Engine.ambient()
	local names = Codecs.register(resolved)
	table.sort(names)
	return names
end

local function __resetForTests()
	sharedHost = nil
end

return {
	createHost = createHost,
	createRuntime = createRuntime,
	animatableTypes = animatableTypes,
	cleanup = Cleanup.cleanup,
	createCleanup = Cleanup.createCleanup,
	createViewport = Viewport.createViewport,
	usableViewportSize = Viewport.usableViewportSize,
	preferredInput = Input.preferredInput,
	preferredInputSpec = Input.preferredInputSpec,
	__resetForTests = __resetForTests,
}
