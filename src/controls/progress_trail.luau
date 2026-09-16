--!strict
-- A damage trail uses the shared motion clock; healing cancels its pending delay.
local trail = {}

function trail.new(core: any, scope: any, source: any, clock: any, options: any, policy: any?): any
	local value = scope:own(clock:glide(source:get(), { duration = options.duration or 0.35, kind = "decorative" }))
	local waiting: any = nil
	local previous = source:get()
	local function cancel()
		if waiting then
			waiting:dispose()
			waiting = nil
		end
	end
	scope:own(cancel)
	if policy then
		scope:own(core:observe(policy, function()
			if clock:isReduced() then
				cancel()
				value:snap(source:get())
			end
		end))
	end
	scope:own(core:observe(source, function()
		local nextValue = source:get()
		cancel()
		if nextValue >= previous or clock:isReduced() then
			value:snap(nextValue)
		else
			value:snap(math.max(value:get(), previous))
			local delay = options.delay or 0.3
			if delay == 0 then
				value:setTarget(nextValue)
			else
				local hold = clock:timer({ from = 0, to = 0, duration = delay, kind = "decorative" })
				waiting = hold
				hold:onSettle(function()
					cancel()
					value:setTarget(source:get())
				end)
			end
		end
		previous = nextValue
	end))
	return value
end

return trail
