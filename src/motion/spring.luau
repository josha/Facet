--!strict
-- Facet spring policy over Compose’s public spring integrator.
-- Compose owns integration; Facet keeps its absolute UI settle threshold,
-- frame-spike limit and gesture velocity handoff. Motion classes are
-- parameterized the way designers ship motion — TWO numbers, never
-- mass/stiffness/damping:
--
--   * dampingRatio (ζ) — overshoot. 1.0 = critically damped (no bounce);
--     < 1.0 overshoots (the one earned `reward` pop, classes.luau).
--   * response (s)     — how quickly the value reaches its target. NOT a
--     duration: settle time emerges from the physics, so an interrupted motion
--     has no duration left to "finish".
--
-- Conversion inside the solver: omega = 2π/response, stiffness = omega²,
-- damping = 2·ζ·omega.
--
-- WHY A SPRING, NOT A TWEEN — the whole reason this module exists: a spring
-- re-targets from its current value AND its current velocity, so it is
-- interruptible and velocity-inheriting by construction. A re-targeted tween
-- hard-cuts velocity to zero, the seam that most separates fluid motion from
-- fine. `setTarget` therefore NEVER touches value or velocity: that is the
-- interruptibility invariant (ui-designer spec I-1), not an implementation
-- detail, and the suite asserts it directly.
--
-- ENGINE-FREE AND CLOCK-FREE. This module never reads a clock and never
-- connects to anything: `step(dt)` is the only way time advances here, so the
-- motion clock (or a scripted test dt) is the single source of time. No
-- RunService, no os.clock, no globals — that is what keeps the whole motion
-- authority headlessly deterministic.
--
-- 2-D motion is TWO scalar springs (see chase.luau), never one spring on a 2-D
-- distance: a single distance spring desyncs when the axes carry different
-- velocities.

local num = require("../num")
local Compose = require("../vendor/compose/core")

local spring = {}

-- dt hygiene: a huge frame (tab-out, stall, a debugger pause) must never blow
-- the integrator up. Clamp the whole frame, then substep so omega·h stays well
-- inside the semi-implicit-Euler stability window even for the stiffest shipped
-- class (`reward`, response 0.18 → omega ≈ 34.9; 34.9 · 1/120 ≈ 0.29 ≪ 2).
local MAX_DT = 0.1
local MAX_SUBSTEP = 1 / 120

-- Settle threshold: within EPS of the target AND slower than EPS/s. Scale-domain
-- springs (0..1 alphas, scales) settle imperceptibly; position-domain springs
-- (hundreds of px) settle a few frames after they visually arrive — which is
-- exactly why perceptual arrival is a RADIUS, not this epsilon (chase.luau).
local DEFAULT_EPS = 1e-3

spring.MAX_DT = MAX_DT
spring.MAX_SUBSTEP = MAX_SUBSTEP
spring.DEFAULT_EPS = DEFAULT_EPS

export type Params = {
	dampingRatio: number,
	response: number,
}

export type Spring = {
	peek: (self: Spring) -> number,
	getVelocity: (self: Spring) -> number,
	getTarget: (self: Spring) -> number,
	setTarget: (self: Spring, target: number) -> (),
	setVelocity: (self: Spring, velocity: number) -> (),
	-- integrate one frame; returns TRUE when the spring is settled (safe to stop
	-- stepping). The caller owns the settle policy — this module has no driver.
	step: (self: Spring, dt: number) -> boolean,
	isSettled: (self: Spring) -> boolean,
	-- value + target set, velocity zeroed: the reduced-motion primitive and the
	-- teardown primitive in one verb.
	snap: (self: Spring, value: number) -> (),
}

-- A non-finite value can never settle (NaN compares false against eps), so it
-- would pin a driver awake forever writing NaN into a property — which blanks
-- the surface permanently. Reject at the boundary and keep the last good state.
local isFinite = num.isFinite

function spring.new(initial: number, params: Params, eps: number?): Spring
	assert(
		type(params) == "table" and type(params.dampingRatio) == "number" and type(params.response) == "number",
		"Facet motion: spring params need numeric dampingRatio and response (resolve a motion class first)"
	)
	assert(isFinite(initial), "Facet motion: a spring needs a finite initial value")

	local response = math.max(params.response, 1e-4)
	local state = Compose.createSpringState({ initial }, 1)
	local aim = { initial }
	local epsilon = if eps ~= nil and isFinite(eps) and eps > 0 then eps else DEFAULT_EPS
	local target = initial

	local self = {}

	-- `peek`, as Compose spells a current-value read
	function self.peek(_: any): number
		return state.position[1]
	end

	function self.getVelocity(_: any): number
		return state.velocity[1]
	end

	function self.getTarget(_: any): number
		return target
	end

	-- Aim at a new target. Does NOT touch value or velocity — motion continues
	-- from where it is, at the speed it has (the interruptibility invariant).
	function self.setTarget(_: any, newTarget: number)
		if not isFinite(newTarget) then
			return -- keep the last good aim (see isFinite)
		end
		target = newTarget
		aim[1] = newTarget
	end

	-- Seed the velocity: the gesture→animation handoff. A release velocity in
	-- px/s becomes the settle motion's opening velocity, so there is no seam
	-- between the finger and the flight. Non-gestural starts seed zero through
	-- the same path (they simply never call this).
	function self.setVelocity(_: any, velocity: number)
		if not isFinite(velocity) then
			return
		end
		state.velocity[1] = velocity
	end

	function self.step(_: any, dt: number): boolean
		if dt > 0 then
			Compose.stepSpring(state, aim, math.min(dt, MAX_DT), response, params.dampingRatio)
		end
		return math.abs(state.position[1] - target) <= epsilon and math.abs(state.velocity[1]) <= epsilon
	end

	function self.isSettled(_: any): boolean
		return math.abs(state.position[1] - target) <= epsilon and math.abs(state.velocity[1]) <= epsilon
	end

	function self.snap(_: any, value: number)
		if not isFinite(value) then
			return
		end
		state.position[1] = value
		target = value
		aim[1] = value
		state.velocity[1] = 0
	end

	return self :: any
end

return spring
