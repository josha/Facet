--!strict

local Active = require "./active"
local Diagnostics = require "../diagnostics"
local Owner = require "./owner"

local function validate(options: unknown, kind: "pool" | "keyed-cache"): (Owner.Owner, number)
	local pool = kind == "pool"
	local name = if pool then "createPool" else "createKeyedCache"
	local build = if pool then "create" else "build"
	local hook = if pool then "reset" else "touch"
	local noun = if pool then "pool" else "cache"
	local settings = options :: { [string]: unknown }
	if type(options) ~= "table" or type(settings[build]) ~= "function" or type(settings.destroy) ~= "function" then
		error(
			Diagnostics.format(kind .. "/invalid-options", name .. " needs " .. build .. " and destroy functions", {
				expected = ("{ %s = function, destroy = function, maxRetained = finite number, %s? = function }"):format(
					build,
					hook
				),
			}),
			0
		)
	end
	for field in settings do
		if field ~= build and field ~= "destroy" and field ~= "maxRetained" and field ~= hook then
			error(
				Diagnostics.format(kind .. "/unknown-option", name .. " was given an option it does not have", {
					option = tostring(field),
					expected = `{build}, destroy, maxRetained, {hook}`,
				}),
				0
			)
		end
	end
	if settings[hook] ~= nil and type(settings[hook]) ~= "function" then
		error(
			Diagnostics.format(
				kind .. "/invalid-" .. hook,
				`{name}.{hook} must be a function`,
				{ actual = Diagnostics.describe(settings[hook]) }
			),
			0
		)
	end
	local owner = Active.current()
	if owner == nil then
		error(
			Diagnostics.format(kind .. "/no-active-owner", name .. " ran outside an owner", {
				contract = `a {noun} cannot outlive the owner responsible for its resources`,
				fix = "create it inside a component or Compose.withOwner(owner, ...)",
			}),
			0
		)
	end
	local limit = settings.maxRetained
	if type(limit) ~= "number" or limit ~= limit or limit < 0 or math.abs(limit) == math.huge then
		error(
			Diagnostics.format(kind .. "/invalid-limit", name .. ".maxRetained must be a finite non-negative number", {
				actual = Diagnostics.describe(limit),
				contract = `a {noun} always has an explicit {if pool then "retained-memory" else "retained-entry"} bound`,
			}),
			0
		)
	end
	return owner, math.floor(limit)
end

local function destroyAll<T>(kind: string, destroy: (T) -> (), visit: ((T) -> ()) -> ())
	local errors: { string } = {}
	visit(function(value)
		local ok, failure: unknown = pcall(destroy, value)
		if not ok then
			table.insert(errors, tostring(failure))
		end
	end)
	if #errors > 0 then
		error(("Compose: %d %s resource destroy failures: %s"):format(#errors, kind, table.concat(errors, "; ")), 0)
	end
end

return { validate = validate, destroyAll = destroyAll }
