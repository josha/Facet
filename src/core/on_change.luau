--!strict
--[[ A CHANGE LISTENER, which Compose does not have a verb for.

	`owner.watchStatic(source, body)` delivers ONCE AT REGISTRATION and then on
	every change. Facet's listeners are the other shape: they react to a surface
	MOVING — a focus that changed, a row that scrolled, a responder that
	resigned — and running them against the value that was already there at
	registration is a spurious event, not a first one.

	So this is that watch with the registration delivery suppressed, and the
	value compared so a re-delivery of an equal value is not a change either
	(NaN compares equal to itself here, as it does everywhere else in Facet).
	It is owned by the owner it is given, and its stop is idempotent.
]]
local function same(a: any, b: any): boolean
	return a == b or (a ~= a and b ~= b)
end

local function onChange(owner: any, source: any, handler: (any) -> ()): () -> ()
	local ready, stopped = false, false
	local last: any = nil
	local stop = owner.watchStatic(source, function(value: any)
		if not ready then
			last = value
			return
		end
		if same(last, value) then
			return
		end
		last = value
		handler(value)
	end)
	ready = true
	return function()
		if stopped then
			return
		end
		stopped = true
		stop()
	end
end

return onChange
