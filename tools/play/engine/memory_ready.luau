--!strict

export type Result = {
	ready: boolean,
	attempts: number,
	elapsed: number,
	tracking: boolean,
	timedOut: boolean,
}

local function waitFor(
	tracking: boolean,
	read: () -> number?,
	clock: () -> number,
	waitFrame: () -> (),
	limit: number
): Result
	local started, attempts = clock(), 0
	while tracking do
		attempts += 1
		local value = read()
		if value ~= nil and value > 0 and value < math.huge then
			return { ready = true, attempts = attempts, elapsed = clock() - started, tracking = true, timedOut = false }
		end
		if clock() - started >= limit then
			break
		end
		waitFrame()
	end
	return {
		ready = false,
		attempts = attempts,
		elapsed = clock() - started,
		tracking = tracking,
		timedOut = tracking,
	}
end

return { waitFor = waitFor }
