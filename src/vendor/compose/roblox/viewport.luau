--!strict

local Compose = require "../core"
local Engine = require "./engine"

export type Viewport = Engine.Viewport

export type Options = Engine.ViewportOptions

local DEFAULT_MINIMUM_SIDE = 100
local DEFAULT_FALLBACK: Viewport = { width = 1280, height = 720 }

local function dimensionsOf(size: Engine.Vector2): Viewport
	return { width = size.X, height = size.Y }
end

local function side(value: unknown, minimum: number): boolean
	return type(value) == "number" and value == value and value >= minimum and value < math.huge
end

local function known(size: Engine.Vector2?, minimum: number?): boolean
	local threshold = if minimum ~= nil then minimum else DEFAULT_MINIMUM_SIDE
	return size ~= nil and side(size.X, threshold) and side(size.Y, threshold)
end

local function createViewport(
	camera: unknown,
	engine: Engine.Engine?,
	options: Options?
): (Compose.ReadOnlyValue<Viewport>, Compose.ReadOnlyValue<boolean>)
	local resolved = if engine ~= nil then engine else Engine.ambient()
	local settings: Options = if options ~= nil then options else {}
	local minimum = if settings.minimumSide ~= nil then settings.minimumSide else DEFAULT_MINIMUM_SIDE
	local fallback = if settings.fallback ~= nil then settings.fallback else DEFAULT_FALLBACK

	local function sizeOf(): Engine.Vector2
		local size = Engine.readMember(camera, "ViewportSize")
		local x, y = Engine.readMember(size, "X"), Engine.readMember(size, "Y")
		assert(type(x) == "number" and type(y) == "number", "Camera viewport must have numeric dimensions")
		return { X = x, Y = y }
	end
	local first = sizeOf()
	local settled = known(first, minimum)
	local value = Compose.cell(if settled then dimensionsOf(first) else fallback)
	local ready = Compose.cell(settled)

	local signal = resolved.propertyChanged(camera, "ViewportSize")
	local connection = signal:Connect(function()
		local size = sizeOf()
		if not known(size, minimum) then
			return
		end
		value:set(dimensionsOf(size))
		ready:set(true)
	end)
	Compose.cleanup(function()
		connection:Disconnect()
	end)
	return value, ready
end

return {
	createViewport = createViewport,
	usableViewportSize = known,
}
