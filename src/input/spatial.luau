--!strict
-- SPATIAL EVENT SEAM (roadmap Step 4; docs/extending/new-platform-mode.md §4;
-- ADR-0021). Contracts only.
--
-- READ THIS FIRST: **Facet does not support VR.** Nothing in this module is a
-- spatial implementation, an adapter, or a capability claim. It is the shape a
-- normalized pointer event may take once a spatial adapter exists, defined now
-- so that adding one later is an adapter change rather than a rewrite of every
-- control. `docs/extending/new-platform-mode.md` §7 lists the physical gates a
-- support claim would first have to pass; none of them has been run.
--
-- THE ONE RULE. A two-dimensional callback must stay correct when the spatial
-- fields are absent. Today's normalized pointer position is
-- `{ x, y, pointerType? }` and every consumer reads `pos.x` / `pos.y`. This
-- module only ever ADDS optional fields beside those, so a Button handler
-- written before spatial existed keeps working, and a drag handler that wants
-- the ray can ask for it. There is no `if vr then` branch anywhere, and adding
-- one to a control would be the mistake the playbook forbids.
--
-- Public interface:
--   spatial.PHASES        -- the closed phase vocabulary
--   spatial.HANDEDNESS    -- the closed handedness vocabulary
--   spatial.normalize(raw) -> Spatial?   -- clamp platform data into the contract
--   spatial.extend(pos, raw) -> pos'     -- attach spatial data to a 2D position
--   spatial.of(pos) -> Spatial?          -- read it back (nil for a flat event)
--   spatial.isFlat(pos) -> boolean       -- true when no spatial data rides along
--   spatial.describe(pos) -> string      -- one-line diagnostic
--
-- Engine-free, non-yielding, and headlessly constructible on purpose: the
-- policy a spatial adapter will drive has to be testable without hardware, or
-- the hardware becomes the only place the policy can be wrong.

local num = require("../num")

local spatial = {}

export type Vec3 = { x: number, y: number, z: number }

-- a selection ray in world space: where the pointing device is and where it
-- points. `length` is the ray's useful extent, not a hit distance.
export type Ray = { origin: Vec3, direction: Vec3, length: number? }

-- the pose of the pointing device or hand. Position plus a forward direction is
-- deliberately weaker than a full transform: a rotation convention Facet has
-- not measured on hardware would be an invented semantic.
export type Pose = { position: Vec3, forward: Vec3? }

export type Spatial = {
	-- where the ray met geometry, in world space (nil = pointing at nothing)
	hit: Vec3?,
	-- the selection ray itself
	ray: Ray?,
	-- the device/hand pose that cast it
	pose: Pose?,
	-- "left" | "right" | "unknown"
	handedness: string,
	-- "began" | "changed" | "ended" | "cancelled" | "none"
	phase: string,
	-- an opaque identifier for what was targeted (a surface id, a part name):
	-- Facet stores and forwards it and never interprets it
	target: string?,
	-- distance from the pose to the hit, when both are known. Derived, not
	-- supplied: a platform that reports a distance disagreeing with its own
	-- geometry would be reporting two different things.
	distance: number?,
}

-- Closed vocabularies. `none` and `unknown` exist so that a partial platform
-- event still produces a well-formed value: a missing phase must not become a
-- nil that every consumer has to guard.
spatial.PHASES = table.freeze({ began = true, changed = true, ended = true, cancelled = true, none = true })
spatial.HANDEDNESS = table.freeze({ left = true, right = true, unknown = true })

local isFiniteNumber = num.isFinite

-- accept { x, y, z } or an engine Vector3-shaped { X, Y, Z }; reject anything
-- that is not three finite numbers. nil-tolerant.
local function vec3(v: any): Vec3?
	if type(v) ~= "table" then
		return nil
	end
	local x = if isFiniteNumber(v.x) then v.x elseif isFiniteNumber(v.X) then v.X else nil
	local y = if isFiniteNumber(v.y) then v.y elseif isFiniteNumber(v.Y) then v.Y else nil
	local z = if isFiniteNumber(v.z) then v.z elseif isFiniteNumber(v.Z) then v.Z else nil
	if x == nil or y == nil or z == nil then
		return nil
	end
	return { x = x, y = y, z = z }
end

local function magnitude(v: Vec3): number
	return math.sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
end

-- unit-length direction, or nil for a degenerate (zero-length) vector. A
-- zero-length "direction" is the malformed platform datum the playbook says to
-- clamp rather than propagate: normalizing it would divide by zero and
-- forwarding it would give every hit test a silent no-op.
local function unit(v: Vec3?): Vec3?
	if v == nil then
		return nil
	end
	local m = magnitude(v)
	if m <= 0 or m ~= m then
		return nil
	end
	return { x = v.x / m, y = v.y / m, z = v.z / m }
end

local function distanceBetween(a: Vec3, b: Vec3): number
	local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
	return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Normalize whatever a platform hands over into the contract, or return nil
-- when there is no spatial content at all. NEVER errors and never yields: a
-- partial or hostile event must degrade to a well-formed value or to nil, so a
-- broken adapter cannot take a screen down.
function spatial.normalize(raw: any): Spatial?
	if type(raw) ~= "table" then
		return nil
	end

	local ray: Ray? = nil
	if type(raw.ray) == "table" then
		local origin = vec3(raw.ray.origin)
		local direction = unit(vec3(raw.ray.direction))
		if origin ~= nil and direction ~= nil then
			local length = if isFiniteNumber(raw.ray.length) and raw.ray.length > 0 then raw.ray.length else nil
			ray = { origin = origin, direction = direction, length = length }
		end
	end

	local pose: Pose? = nil
	if type(raw.pose) == "table" then
		local position = vec3(raw.pose.position)
		if position ~= nil then
			pose = { position = position, forward = unit(vec3(raw.pose.forward)) }
		end
	end

	local hit = vec3(raw.hit)

	local handedness = if type(raw.handedness) == "string" and spatial.HANDEDNESS[raw.handedness]
		then raw.handedness
		else "unknown"
	local phase = if type(raw.phase) == "string" and spatial.PHASES[raw.phase] then raw.phase else "none"
	local target = if type(raw.target) == "string" and raw.target ~= "" then raw.target else nil

	-- nothing spatial was actually supplied: a bare { phase = "none" } is not a
	-- spatial event, and pretending it is would make every flat event look
	-- spatially targeted
	if ray == nil and pose == nil and hit == nil and target == nil then
		return nil
	end

	-- distance is DERIVED from the geometry we were given, never taken on trust
	local distance: number? = nil
	if hit ~= nil then
		local from = if pose ~= nil then pose.position elseif ray ~= nil then ray.origin else nil
		if from ~= nil then
			distance = distanceBetween(from, hit)
		end
	end

	return {
		hit = hit,
		ray = ray,
		pose = pose,
		handedness = handedness,
		phase = phase,
		target = target,
		distance = distance,
	}
end

-- Attach spatial data to a normalized 2D pointer position, returning a NEW
-- table. The 2D fields are copied through untouched — that is the whole
-- compatibility promise: `pos.x` and `pos.y` mean exactly what they meant
-- before, and a consumer that never looks at `pos.spatial` cannot tell the
-- difference. When there is no spatial content the input is returned unchanged.
function spatial.extend(pos: any, raw: any): any
	local normalized = spatial.normalize(raw)
	if normalized == nil then
		return pos
	end
	local out = if type(pos) == "table" then table.clone(pos) else {}
	out.spatial = normalized
	return out
end

function spatial.of(pos: any): Spatial?
	if type(pos) ~= "table" then
		return nil
	end
	return pos.spatial
end

-- A flat event is the default and the overwhelming majority: a mouse click, a
-- finger tap, a gamepad activation. Controls do not branch on this — it exists
-- for diagnostics and for the handful of interactions (placing, targeting) that
-- genuinely need the third dimension.
function spatial.isFlat(pos: any): boolean
	return spatial.of(pos) == nil
end

function spatial.describe(pos: any): string
	local s = spatial.of(pos)
	if s == nil then
		return "flat"
	end
	local parts = { `phase={s.phase}`, `hand={s.handedness}` }
	if s.ray ~= nil then
		table.insert(parts, "ray")
	end
	if s.pose ~= nil then
		table.insert(parts, "pose")
	end
	if s.hit ~= nil then
		table.insert(parts, if s.distance ~= nil then string.format("hit@%.2f", s.distance) else "hit")
	end
	if s.target ~= nil then
		table.insert(parts, `target={s.target}`)
	end
	return table.concat(parts, " ")
end

return spatial
