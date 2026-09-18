--!strict
--!native

local UPDATE_RATE = 120
local FIXED_STEP = 1 / UPDATE_RATE

local MAX_DELTA = 0.25

export type State = {
	position: { number },
	velocity: { number },
	arity: number,
}

local function createState(position: { number }, arity: number): State
	local start = table.create(arity, 0)
	local velocity = table.create(arity, 0)
	for index = 1, arity do
		start[index] = position[index]
		velocity[index] = 0
	end
	return { position = start, velocity = velocity, arity = arity }
end

local function coefficients(period: number, damping: number): (number, number)
	local frequency = 2 * math.pi / period
	return frequency * frequency, 2 * damping * frequency
end

local function step(state: State, target: { number }, delta: number, period: number, damping: number): number
	if delta <= 0 then
		return 0
	end
	local simulated = math.min(delta, MAX_DELTA)
	local stiffness, drag = coefficients(period, damping)

	local position = state.position
	local velocity = state.velocity
	local arity = state.arity

	local remaining = simulated
	while remaining > 0 do
		local h = if remaining > FIXED_STEP then FIXED_STEP else remaining
		remaining -= h
		for index = 1, arity do
			local offset = position[index] - target[index]
			local acceleration = -stiffness * offset - drag * velocity[index]
			local nextVelocity = velocity[index] + acceleration * h
			velocity[index] = nextVelocity
			position[index] += nextVelocity * h
		end
	end

	return simulated
end

local function atRest(state: State, target: { number }, reference: { number }, tolerance: number): boolean
	local position = state.position
	local velocity = state.velocity
	for index = 1, state.arity do
		local travelled = math.abs(reference[index] - target[index])

		local epsilon = math.max(travelled * tolerance, tolerance)
		if math.abs(position[index] - target[index]) > epsilon then
			return false
		end
		if math.abs(velocity[index]) * FIXED_STEP > epsilon then
			return false
		end
	end
	return true
end

local function settle(state: State, target: { number })
	local position = state.position
	local velocity = state.velocity
	for index = 1, state.arity do
		position[index] = target[index]
		velocity[index] = 0
	end
end

return {
	UPDATE_RATE = UPDATE_RATE,
	MAX_DELTA = MAX_DELTA,
	createState = createState,
	coefficients = coefficients,
	step = step,
	atRest = atRest,
	settle = settle,
}
