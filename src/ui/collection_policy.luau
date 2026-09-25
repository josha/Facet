--!strict
local policy = {}
function policy.allows<V>(predicate: ((V) -> boolean)?, item: V): boolean
	if predicate == nil then
		return true
	end
	local ok, allowed = pcall(predicate, item)
	return ok and allowed == true
end
function policy.disabled<V>(predicate: ((V) -> boolean)?, item: V): boolean
	if predicate == nil then
		return false
	end
	local ok, disabled = pcall(predicate, item)
	return not ok or disabled == true
end
return policy
