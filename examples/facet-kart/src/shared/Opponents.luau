--!strict

export type Driver = {
	progress: number,
	lane: number,
	targetLane: number,
	speed: number,
	pace: number,
	phase: number,
	controlled: boolean,
	halfWidth: number,
}

local Opponents = { gap = 0.025, breadth = 8.1, laneRate = 5, step = 1 / 60 }
local lanes = { -8.25, 0, 8.25 }

function Opponents.create(index: number, seed: number): Driver
	local value = (seed + index * 48271) % 2147483647
	value = value * 48271 % 2147483647
	return {
		progress = 0.05 - math.floor((index - 1) / 3) * Opponents.gap,
		lane = lanes[(index - 1) % 3 + 1],
		targetLane = lanes[(index - 1) % 3 + 1],
		speed = 0,
		pace = 0.045 + value / 2147483647 * 0.009,
		phase = value % 628 / 100,
		controlled = true,
		halfWidth = Opponents.breadth / 2,
	}
end

local function distance(a: number, b: number): number
	return (b - a + 0.5) % 1 - 0.5
end

function Opponents.stepField(field: { Driver }, dt: number, clock: number)
	for _, driver in field do
		if not driver.controlled then
			continue
		end
		local function clearance(lane: number, changing: boolean): number
			local gap = 0.15
			for _, other in field do
				if other == driver then
					continue
				end
				local breadth = driver.halfWidth + other.halfWidth
				local low = (if changing then math.min(driver.lane, lane) else lane) - breadth
				local high = (if changing then math.max(driver.lane, lane) else lane) + breadth
				local otherLow = math.min(other.lane, other.targetLane)
				local otherHigh = math.max(other.lane, other.targetLane)
				if otherHigh > low and otherLow < high then
					local delta = distance(driver.progress, other.progress)
					if lane ~= driver.lane and delta < 0 and delta > -0.07 then
						return 0
					end
					if changing and math.abs(delta) < Opponents.gap - 1e-8 then
						return 0
					end
					if delta >= 0 then
						gap = math.min(gap, delta)
					end
				end
			end
			return gap
		end
		local gap = clearance(driver.targetLane, false)
		if gap < 0.085 and math.abs(driver.lane - driver.targetLane) < 0.01 then
			local best = gap
			for _, lane in lanes do
				if math.abs(lane - driver.lane) <= 8.3 then
					local available = clearance(lane, false)
					if available > best + 0.01 then
						best = available
						driver.targetLane = lane
					end
				end
			end
		end
		local change = math.clamp(driver.targetLane - driver.lane, -Opponents.laneRate * dt, Opponents.laneRate * dt)
		if clearance(driver.lane + change, true) > 0 then
			driver.lane += change
		end
		gap = clearance(driver.lane, false)
		local desired = driver.pace * (1 + 0.045 * math.sin(clock * 0.7 + driver.phase))
		driver.speed =
			math.min(driver.speed + 0.025 * dt, desired, math.max(0, (gap - Opponents.gap) / math.max(dt, 0.6)))
		driver.progress += driver.speed * dt
	end
end

return Opponents
