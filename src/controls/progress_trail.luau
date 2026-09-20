--!strict
-- A damage trail uses the shared motion clock; healing cancels its pending delay.
local Compose = require("../vendor/compose/core")
local read = require("../selection_model").read
local trail = {}

-- Compose drives a finite delay-and-fall sequence. Healing cancels it immediately.
function trail.native(runtime, source, options, policy)
	local initial = read(source)
	local from, target = Compose.cell(initial), Compose.cell(initial)
	local delay, duration = options.delay or 0.3, options.duration or 0.35
	local total = delay + duration
	local clock = runtime.timeline({ duration = total, autoplay = false })
	clock:seek(total)
	local value = Compose.formula(function(use)
		local progress = math.clamp((use(clock.progress) * total - delay) / duration, 0, 1)
		return use(from) + (use(target) - use(from)) * progress
	end)
	local previous = initial
	Compose.watch(function(use)
		local nextValue = use(source)
		local reduced = policy and use(policy) == "reduced"
		if nextValue >= previous or reduced then
			from:set(nextValue)
			target:set(nextValue)
			clock:seek(total)
		else
			from:set(math.max(value:peek(), previous))
			target:set(nextValue)
			clock:restart()
		end
		previous = nextValue
	end)
	return value
end

return trail
