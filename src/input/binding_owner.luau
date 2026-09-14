--!strict
-- Shared held-input provenance and ownership checks; event delivery remains engine-owned.
local owner = {}
function owner.isGamepadKeyCode(keyCode: string): boolean
	return keyCode:match("^Button") ~= nil or keyCode:match("^DPad") ~= nil or keyCode:match("^Thumbstick") ~= nil
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
