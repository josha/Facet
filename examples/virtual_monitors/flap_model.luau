--!strict
local flap = {
	WIDTH = 768,
	HEIGHT = 448,
	TILE = 32,
	GROUND_ROW = 12,
	BIRD_X = 160,
	BIRD_RADIUS = 12,
	FIRST_PIPE = 18,
	PIPE_SPACING = 9,
	PIPE_WIDTH = 2,
	GAP_ROWS = 5,
	SPEED = 150,
	GRAVITY = 950,
	IMPULSE = -310,
}

export type State = {
	phase: "ready" | "playing" | "paused" | "over",
	x: number,
	y: number,
	velocity: number,
	score: number,
}

function flap.gapRow(index: number): number
	return 3 + (index * 7) % 4
end

function flap.tileAt(column: number, row: number): string?
	if row == flap.GROUND_ROW then
		return "grass"
	elseif row > flap.GROUND_ROW and row < flap.HEIGHT / flap.TILE then
		return "earth"
	elseif row < 0 or row >= flap.GROUND_ROW or column < flap.FIRST_PIPE then
		return nil
	end
	local relative = column - flap.FIRST_PIPE
	if relative % flap.PIPE_SPACING >= flap.PIPE_WIDTH then
		return nil
	end
	local gap = flap.gapRow(math.floor(relative / flap.PIPE_SPACING))
	if row >= gap and row < gap + flap.GAP_ROWS then
		return nil
	end
	return if row == gap - 1 or row == gap + flap.GAP_ROWS then "cap" else "pipe"
end

local function initial(): State
	return { phase = "ready" :: "ready", x = 0, y = 192, velocity = 0, score = 0 }
end

local function collision(state: State): boolean
	local radius, tile = flap.BIRD_RADIUS, flap.TILE
	if state.y - radius <= 0 or state.y + radius >= flap.GROUND_ROW * tile then
		return true
	end
	local x = state.x + flap.BIRD_X
	for row = math.floor((state.y - radius) / tile), math.floor((state.y + radius - 0.001) / tile) do
		for column = math.floor((x - radius) / tile), math.floor((x + radius - 0.001) / tile) do
			if flap.tileAt(column, row) ~= nil then
				return true
			end
		end
	end
	return false
end

function flap.new(Compose: typeof(require("@repo/src/vendor/compose/core")))
	local state, best = Compose.cell(initial()), Compose.cell(0)
	local disposed = false
	local function flapPress()
		if disposed then
			return
		end
		local current = state:peek()
		local nextState: State = if current.phase == "ready" or current.phase == "over"
			then initial()
			else table.clone(current)
		nextState.phase = "playing" :: "playing"
		nextState.velocity = flap.IMPULSE
		state:set(nextState)
	end
	local function pause()
		if disposed or state:peek().phase ~= "playing" then
			return
		end
		local nextState = table.clone(state:peek())
		nextState.phase = "paused" :: "paused"
		state:set(nextState)
	end
	local function togglePause()
		if disposed then
			return
		end
		if state:peek().phase == "paused" then
			local nextState = table.clone(state:peek())
			nextState.phase = "playing" :: "playing"
			state:set(nextState)
		else
			pause()
		end
	end
	local function step(dt: number)
		if disposed or state:peek().phase ~= "playing" or dt <= 0 or dt ~= dt then
			return
		end
		local nextState = table.clone(state:peek())
		local remaining = math.min(dt, 0.1)
		while remaining > 0 do
			local delta = math.min(remaining, 1 / 120)
			remaining -= delta
			nextState.x += flap.SPEED * delta
			nextState.y += nextState.velocity * delta + flap.GRAVITY * delta * delta / 2
			nextState.velocity += flap.GRAVITY * delta
			if collision(nextState) then
				nextState.phase = "over" :: "over"
				break
			end
			local passed = (nextState.x + flap.BIRD_X - flap.BIRD_RADIUS) / flap.TILE
				- flap.FIRST_PIPE
				- flap.PIPE_WIDTH
			nextState.score = if passed >= 0 then math.floor(passed / flap.PIPE_SPACING) + 1 else 0
		end
		if nextState.score > best:peek() then
			best:set(nextState.score)
		end
		state:set(nextState)
	end
	return {
		state = state,
		best = best,
		flap = flapPress,
		pause = pause,
		togglePause = togglePause,
		step = step,
		dispose = function()
			disposed = true
		end,
	}
end

return flap
