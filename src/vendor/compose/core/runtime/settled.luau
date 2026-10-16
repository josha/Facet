--!strict

local Host = require "../host"
local Owner = require "../ownership/owner"
local Types = require "../reactive/types"
local Cell = require "../reactive/cell"
local Support = require "../structure/support"
local ownedFrame = require "../ownership/frame"

export type Options<T, R = unknown> = {
	sample: () -> T,
	frames: number?,
	equals: Types.Equals<T>?,
	restart: Types.Source<R>?,
	ready: (() -> boolean)?,
	timeout: number?,
}

return function(host: Host.Host, ownerOf: (string) -> Owner.Owner)
	return function<T, R>(options: Options<T, R>): Types.Readable<boolean>
		local owner = ownerOf "settled"
		local frames = assert(host.frames, "Compose settled requires host.frames")
		local count = options.frames or 2
		assert(count >= 1 and count < math.huge and count % 1 == 0, "Compose settled frames must be a positive integer")
		assert(
			options.timeout == nil or (options.timeout >= 0 and options.timeout < math.huge),
			"Compose settled timeout must be finite and nonnegative"
		)
		local value = Cell.cell(false)
		local pump: ownedFrame.Pump
		local generation = 0
		local function halt()
			generation += 1
			pump.stop()
		end
		local last: T? = nil
		local equal: Types.Equals<T> = options.equals or Cell.defaultEquals
		local stable, waited = 0, 0
		pump = ownedFrame(owner, frames.onFrame, function(delta)
			if options.ready and not options.ready() then
				stable, waited = 0, 0
				return
			end
			local mine = generation
			local current = options.sample()
			if mine ~= generation or owner.isDisposed() then
				return
			end
			waited += delta
			stable = if stable > 0 and equal(last :: T, current) then stable + 1 else 1
			last = current
			if stable >= count or (options.timeout ~= nil and waited >= options.timeout) then
				halt()
				value:set(true)
			end
		end)
		local function track()
			halt()
			if owner.isDisposed() then
				return
			end
			value:set(false)
			last, stable, waited = nil, 0, 0
			pump.start()
		end
		if options.restart then
			local source = Support.sourceOf(options.restart, "settled", "restart") :: Types.Body<R>
			local seen: R? = nil
			local initialized = false
			owner.watch(function(use)
				local key = source(use)
				if not initialized or key ~= seen then
					initialized, seen = true, key
					track()
				end
			end)
		else
			track()
		end
		return value
	end
end
