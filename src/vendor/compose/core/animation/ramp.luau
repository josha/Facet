--!strict

local CoreTypes = require "../types"
local Reactors = require "../reactive/reactor"
local Diagnostics = require "../diagnostics"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local cellModule = require "../reactive/cell"

export type Options = CoreTypes.RampOptions

export type Ramp<T> = CoreTypes.Ramp<T>

local DEFAULT_SECONDS = 0.25

local function createRamps<T>(
	tween: (
		source: Types.Body<T>,
		options: CoreTypes.TweenOptions?
	) -> Types.ReadOnlyValue<T>,
	requireOwner: (operation: string) -> Owner.Owner
): (initial: T, options: Options?) -> Ramp<T>
	return function(initial: T, options: Options?): Ramp<T>
		local owner = requireOwner "ramp"
		local target = cellModule.cell(initial)
		local seconds = cellModule.cell(DEFAULT_SECONDS)
		local instant = cellModule.cell(false)
		local value = tween(function(use: Types.Use): T
			return use(target)
		end, {
			seconds = seconds,
			ease = if options ~= nil then options.ease else nil,
			reducedMotion = instant,
		})
		return {
			value = value,
			retarget = function(next: T, duration: number)
				if type(duration) ~= "number" or duration ~= duration or duration == math.huge then
					return Diagnostics.raise("ramp/invalid-seconds", "a ramp needs a finite duration", {
						actual = Diagnostics.describe(duration),
						expected = "seconds; zero or less jumps to the target at once",
					})
				end
				Reactors.batch(Owner.reactorOf(owner), function()
					if duration > 0 then
						seconds:set(duration)
					end
					instant:set(duration <= 0)
					target:set(next)
				end)
			end,
		}
	end
end

return {
	createRamps = createRamps,
}
