--!strict
-- Headless Lune scheduler provider for vendored Fusion 0.3.
-- Public interface: setup() binds the provider and returns { step = fn } to
-- drain deferred/immediate tasks and advance Fusion's update step.
-- Adapted from Fusion's own test/SpecExternal.luau (queue of coroutines);
-- depends on vendor/Fusion/External only. Tests MUST call setup() before
-- constructing any Fusion state under Lune (init.luau skips RobloxExternal
-- when `game` is nil — see the vendor patch there).

local External = require("../../vendor/Fusion/External")

local LuneExternal = {}

LuneExternal.policies = {
	allowWebLinks = false,
}

local queue = {} :: { thread }

-- Runs synchronously. SpecExternal's queue-and-yield variant assumes an outer
-- scheduler loop owns the calling thread; under Lune's main thread that yield
-- silently ends the script (observed: suite truncated with exit 0). Direct
-- invocation matches RobloxExternal's task.spawn "run now" semantics for the
-- deterministic-test case.
function LuneExternal.doTaskImmediate(resume: () -> ())
	resume()
end

function LuneExternal.doTaskDeferred(resume: () -> ())
	table.insert(queue, coroutine.create(resume))
end

function LuneExternal.logErrorNonFatal(errorString: string): ()
	-- deterministic tests: quarantine, do not print
end

function LuneExternal.logWarn(errorString: string): ()
	-- deterministic tests: quarantine, do not print
end

local doUpdateSteps = false

function LuneExternal.startScheduler()
	doUpdateSteps = true
end

function LuneExternal.stopScheduler()
	doUpdateSteps = false
end

-- Drains the task queue; advances Fusion's update step when started.
local function step(currentTime: number)
	if doUpdateSteps then
		External.performUpdateStep(currentTime)
	end
	while true do
		local nextTask = table.remove(queue, 1)
		if nextTask == nil then
			break
		end
		local ok, result = coroutine.resume(nextTask)
		if not ok then
			error("fusion_lune_external scheduler task failed: " .. tostring(result))
		end
	end
end

function LuneExternal.setup(): { step: (number) -> () }
	External.setExternalProvider(LuneExternal :: any)
	return { step = step }
end

return LuneExternal
