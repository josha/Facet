--!strict
--[[ A scenario keeps its state outside the screen it presents, so its steps can
	drive that state whether or not the screen is mounted. What the state starts
	outside a component — motion values, watches, presenter subscriptions — has no
	mount to release it, so it belongs to this owner instead, and the scenario's
	`dispose` releases the owner. ]]

return function(Compose: any)
	local root = Compose.createRootOwner(function() end)
	local lifetime = {}

	local function under<T...>(body: () -> T...): T...
		return Compose.withOwner(root.owner, body)
	end

	-- Releases `value` with the scenario: a disconnect function, or anything
	-- with a `dispose`. Answers the value, so a declaration can wrap itself.
	function lifetime.own<T>(value: T): T
		local held: any = value
		under(function()
			Compose.cleanup(function()
				if type(held) == "function" then
					held()
				else
					held:dispose()
				end
			end)
		end)
		return value
	end

	-- A watch that lives as long as the scenario. It runs once immediately.
	function lifetime.watch(body: (use: any) -> ())
		under(function()
			Compose.watch(body)
		end)
	end

	-- Calls `onChange` with each new value of `source`, not with the current one.
	function lifetime.observe(source: any, onChange: (value: any) -> ())
		local first = true
		lifetime.watch(function(use)
			local value = use(source)
			if first then
				first = false
				return
			end
			onChange(value)
		end)
	end

	-- Runs `body` with the scenario's owner active, for anything else that must
	-- be created under one.
	lifetime.under = under
	lifetime.dispose = root.dispose
	return lifetime
end
