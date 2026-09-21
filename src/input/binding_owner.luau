--!strict
-- Shared held-input provenance and ownership checks; event delivery remains engine-owned.
local owner = {}
function owner.isGamepadKeyCode(keyCode: string): boolean
	return keyCode:match("^Button") ~= nil or keyCode:match("^DPad") ~= nil or keyCode:match("^Thumbstick") ~= nil
end

-- Hints follow the resolved device class; the engine breaks ties only inside it.
function owner.matchesClass(binding: any, preferredInput: string): boolean
	if binding == nil then
		return false
	end
	if preferredInput == "Touch" then
		return binding.uiButton ~= nil
	end
	if binding.keyCode == nil then
		return false
	end
	return owner.isGamepadKeyCode(binding.keyCode) == (preferredInput == "Gamepad")
end

function owner.preferredBinding(bindings: { any }, preferredInput: string, enginePreferred: any?): any
	if enginePreferred ~= nil and owner.matchesClass(enginePreferred, preferredInput) then
		for _, binding in bindings do
			if binding == enginePreferred then
				return binding
			end
		end
	end
	local fallback: any = nil
	for _, binding in bindings do
		if preferredInput == "Touch" then
			if binding.uiButton ~= nil then
				return binding
			end
		elseif binding.keyCode ~= nil then
			if owner.matchesClass(binding, preferredInput) then
				return binding
			end
			if fallback == nil then
				fallback = binding
			end
		end
	end
	return fallback
end

function owner.actionNamed(contexts: { any }, name: string, prefer: any?): any
	if prefer ~= nil and not prefer.destroyed then
		for _, action in prefer.actions do
			if action.name == name then
				return action
			end
		end
	end
	local best: any = nil
	local bestPriority: number? = nil
	for _, context in contexts do
		if context.enabled and not context.destroyed and (bestPriority == nil or context.priority > bestPriority) then
			for _, action in context.actions do
				if action.name == name then
					best, bestPriority = action, context.priority
					break
				end
			end
		end
	end
	return best
end

function owner.wouldWin(contexts: { any }, context: any, binding: any): boolean
	if context == nil or binding == nil or context.destroyed or not context.enabled or binding.removed then
		return false
	end
	local candidates: { any } = {}
	for _, candidateContext in contexts do
		if candidateContext.enabled and not candidateContext.destroyed then
			for _, action in candidateContext.actions do
				for _, candidateBinding in action.bindings do
					local matches = if binding.isAxis == true
						then candidateBinding.isAxis == true and candidateBinding.axis == binding.axis
						else binding.keyCode ~= nil and candidateBinding.keyCode == binding.keyCode
					if matches then
						table.insert(candidates, candidateContext)
						break
					end
				end
			end
		end
	end
	table.sort(candidates, function(a, b)
		return a.priority > b.priority
	end)
	local consumedPriority: number? = nil
	for _, candidateContext in candidates do
		if consumedPriority ~= nil and candidateContext.priority < consumedPriority then
			break -- sunk by a higher-priority context before reaching ours
		end
		if candidateContext == context then
			return true
		end
		if candidateContext.sink then
			consumedPriority = candidateContext.priority
		end
	end
	return false
end
return owner
