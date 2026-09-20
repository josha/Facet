--!strict

local Compose = require "../core"
local Engine = require "./engine"

export type Viewport = { width: number, height: number }

export type Options = {
	minimumSide: number?,
	fallback: Viewport?,
}

local DEFAULT_MINIMUM_SIDE = 100
local DEFAULT_FALLBACK: Viewport = { width = 1280, height = 720 }

local function dimensionsOf(size: any): Viewport
	return { width = size.X, height = size.Y }
end

local function side(value: any, minimum: number): boolean
	return type(value) == "number" and value == value and value >= minimum and value < math.huge
end

local function known(size: any, minimum: number?): boolean
	local threshold = if minimum ~= nil then minimum else DEFAULT_MINIMUM_SIDE
	return size ~= nil and side(size.X, threshold) and side(size.Y, threshold)
end

local function createViewport(
	camera: any,
	engine: Engine.Engine?,
	options: Options?
): (Compose.Readable<Viewport>, Compose.Readable<boolean>)
	local resolved = if engine ~= nil then engine else Engine.ambient()
	local settings = if options ~= nil then options else {} :: Options
	local minimum = if settings.minimumSide ~= nil then settings.minimumSide else DEFAULT_MINIMUM_SIDE
	local fallback = if settings.fallback ~= nil then settings.fallback else DEFAULT_FALLBACK

	local first = camera.ViewportSize
	local settled = known(first, minimum)
	local value = Compose.cell(if settled then dimensionsOf(first) else fallback)
	local ready = Compose.cell(settled)

	local signal = resolved.propertyChanged(camera, "ViewportSize")
	local connection = signal:Connect(function()
		local size = camera.ViewportSize
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
