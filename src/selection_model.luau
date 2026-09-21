--!strict
-- Shared selection decisions. Rendering never reconciles caller-owned values.
local Compose = require("./vendor/compose/core")
local model = {}
function model.read(value: any, use: Compose.Use?): any
	if type(value) == "function" then
		return if use then value(use) else Compose.sample(value)
	end
	if Compose.isReadable(value) then
		return if use then use(value) else value:peek()
	end
	return value
end
function model.isSource(value)
	return type(value) == "function" or Compose.isReadable(value)
end
function model.isWritable(value)
	return type(value) == "table" and type(value.set) == "function" and Compose.isReadable(value)
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
