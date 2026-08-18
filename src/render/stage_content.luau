--!strict
-- THE STAGE CONTENT SEAM'S RULINGS (UI.Stage; research
-- docs/research/2026-08-08-viewportframe-engine-facts.md).
--
-- PURE and engine-free, so BOTH adapters go through it: the live ScreenTarget
-- (which turns the answers into CFrame/Color3/Vector3 writes on an owned Camera
-- and the frame itself) and the headless recording twin the suite drives. A
-- normalizer each adapter wrote for itself would be two rulings on one contract,
-- which is how "headless green, device wrong" ships (the SF-M9 lesson).
--
-- The boundary is deliberately ENGINE-TYPE-FREE: a point/direction is
-- `{ x, y, z }` and a colour is `{ r, g, b }` in 0..1 — the same shape the theme
-- tokens already speak — so nothing above `src/client/` has to know a Vector3
-- exists. Refusals are immediate and name the field (constitution §4): a stage
-- that silently ignores half a camera is a black box nobody can debug.

local spec_guard = require("../spec_guard")
local num = require("../num")

local stage_content = {}

local CAMERA_KEYS: spec_guard.KeySet = table.freeze({ position = true, lookAt = true, fov = true })
local LIGHTING_KEYS: spec_guard.KeySet = table.freeze({ ambient = true, lightColor = true, lightDirection = true })

local isFinite = num.isFinite

-- a point or a direction: three finite numbers, frozen
local function vec3(where: string, field: string, value: any): { x: number, y: number, z: number }
	if type(value) ~= "table" or not (isFinite(value.x) and isFinite(value.y) and isFinite(value.z)) then
		error(
			`Facet {where}.{field} expects a vector table `
				.. "{ x = <number>, y = <number>, z = <number> }, got "
				.. `{typeof(value)}. Fix: pass plain numbers — the adapter converts to the engine type.`,
			0
		)
	end
	return table.freeze({ x = value.x :: number, y = value.y :: number, z = value.z :: number })
end

-- a colour: three finite 0..1 channels, clamped like every other token colour
local function rgb(where: string, field: string, value: any): { r: number, g: number, b: number }
	if type(value) ~= "table" or not (isFinite(value.r) and isFinite(value.g) and isFinite(value.b)) then
		error(
			`Facet {where}.{field} expects a colour table `
				.. "{ r = 0..1, g = 0..1, b = 0..1 }, got "
				.. `{typeof(value)}. Fix: pass 0-1 floats, the same shape the theme tokens use.`,
			0
		)
	end
	return table.freeze({
		r = math.clamp(value.r :: number, 0, 1),
		g = math.clamp(value.g :: number, 0, 1),
		b = math.clamp(value.b :: number, 0, 1),
	})
end

export type Camera = {
	position: { x: number, y: number, z: number },
	lookAt: { x: number, y: number, z: number },
	fov: number?,
}

export type Lighting = {
	ambient: { r: number, g: number, b: number }?,
	lightColor: { r: number, g: number, b: number }?,
	lightDirection: { x: number, y: number, z: number }?,
}

-- normalizeCamera(spec) -> frozen Camera. `position` and `lookAt` are BOTH
-- required: a camera aimed from nowhere, or at nothing, renders an empty box and
-- reports nothing, so half a camera is refused rather than half-applied. `fov` is
-- optional (absent = leave the engine's own field of view alone) and is clamped to
-- the engine's legal 1..120 range rather than silently rejected at the write site.
function stage_content.normalizeCamera(spec: any): Camera
	if type(spec) ~= "table" then
		error(`Facet stageHost.setCamera expects a spec table, got {typeof(spec)}`, 0)
	end
	spec_guard.assertKnownKeys("stageHost.setCamera", spec, CAMERA_KEYS, "spec")
	local camera: any = {
		position = vec3("stageHost.setCamera", "position", spec.position),
		lookAt = vec3("stageHost.setCamera", "lookAt", spec.lookAt),
	}
	-- A DEGENERATE CAMERA IS REFUSED HERE, in the shared normalizer, not in an
	-- adapter (platform review M2: the guard lived only in the live adapter, so
	-- the headless twin RECORDED a camera the live path THROWS on — the exact
	-- "headless green, device wrong" split this module exists to prevent). An
	-- eye sitting on its target has no look direction; and refusal-before-write
	-- means the camera stays exactly where it was on both adapters.
	do
		local dx = camera.lookAt.x - camera.position.x
		local dy = camera.lookAt.y - camera.position.y
		local dz = camera.lookAt.z - camera.position.z
		if (dx * dx + dy * dy + dz * dz) <= 1e-8 then
			error(
				"Facet stageHost.setCamera: position and lookAt are the same point — "
					.. "a camera with no direction cannot render. Move one of them.",
				0
			)
		end
	end
	if spec.fov ~= nil then
		if not isFinite(spec.fov) then
			error(`Facet stageHost.setCamera.fov expects a number (degrees), got {typeof(spec.fov)}`, 0)
		end
		camera.fov = math.clamp(spec.fov :: number, 1, 120)
	end
	return table.freeze(camera)
end

-- normalizeLighting(spec) -> frozen Lighting. Every field is optional and each is
-- applied independently, so a caller may set only the ambient; an EMPTY spec is
-- refused, because "set the lighting to nothing" is always a mistake and silently
-- doing nothing is the accepted-and-ignored failure this framework keeps closing.
function stage_content.normalizeLighting(spec: any): Lighting
	if type(spec) ~= "table" then
		error(`Facet stageHost.setLighting expects a spec table, got {typeof(spec)}`, 0)
	end
	spec_guard.assertKnownKeys("stageHost.setLighting", spec, LIGHTING_KEYS, "spec")
	local lighting: any = {}
	if spec.ambient ~= nil then
		lighting.ambient = rgb("stageHost.setLighting", "ambient", spec.ambient)
	end
	if spec.lightColor ~= nil then
		lighting.lightColor = rgb("stageHost.setLighting", "lightColor", spec.lightColor)
	end
	if spec.lightDirection ~= nil then
		lighting.lightDirection = vec3("stageHost.setLighting", "lightDirection", spec.lightDirection)
	end
	if next(lighting) == nil then
		error(
			"Facet stageHost.setLighting: the spec declares nothing. Pass at least one of "
				.. "ambient / lightColor / lightDirection.",
			0
		)
	end
	return table.freeze(lighting)
end

-- the refusal a handle whose node has died answers, spelled once so both adapters
-- say the same thing (and a caller can match on it)
function stage_content.disposedError(path: string): string
	return `Facet stageHost: the Stage node '{path}' has been disposed — its handle is dead. `
		.. "Ask controller.stageHost(path) again after the node remounts."
end

return table.freeze(stage_content)
