--!strict
-- Shared selection decisions. Rendering never reconciles caller-owned values.
local model = {}
function model.read(value, use)
	if type(value) == "table" and (value.kind == "signal" or value.kind == "memo") then
		return if use then use(value) else value:get()
	end
	return value
end
function model.identity(option)
	return if option.value ~= nil then option.value else option.id
end
function model.find(options, identity)
	for _, option in options do
		if not option.divider and model.identity(option) == identity then
			return option
		end
	end
	return nil
end
function model.enabled(option)
	return option ~= nil and model.read(option.enabled) ~= false
end
function model.choose(options, current, proposed, required, accepts)
	if proposed == nil then
		if required ~= false then
			return false, current
		end
	elseif not model.enabled(model.find(options, proposed)) then
		return false, current
	end
	if proposed == current then
		return false, current
	end
	if accepts then
		local ok, result = pcall(accepts, proposed, current)
		if not ok or result == false then
			return false, current
		end
	end
	return true, proposed
end
return table.freeze(model)
