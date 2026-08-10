--!strict
-- The proof's DOMAIN clock: the one source of time every fake service reads.
--
-- It is not the motion clock and it is not `os.clock`. Domain time advances only
-- when someone advances it — the scenario's `advance` step, or the presenter's
-- own tick in a live place — so "same seed + same steps => identical dump" holds
-- by construction, and nothing in this proof can read wall time by accident.
--
-- `now` is a SIGNAL as well as a number, because everything time-derived in the
-- UI (a countdown's M:SS, a depleting bar, an arrival) is a memo over it. One
-- advance is one write and one flush, whatever it wakes.
local clock = {}

export type Scheduled = { at: number, seq: number, fn: () -> (), cancelled: boolean }

function clock.new(core: any, opts: { start: number? }?): any
	local options = opts or {}
	local nowSignal = core:signal(options.start or 0)
	local scheduled: { Scheduled } = {}
	local seq = 0
	local self: any = { nowSignal = nowSignal }

	function self.now(): number
		return nowSignal:get()
	end

	-- run `fn` once, `delay` seconds of domain time from now. The returned
	-- handle cancels it — a command that is superseded must not resolve twice.
	function self.after(delay: number, fn: () -> ()): any
		seq += 1
		local entry: Scheduled = { at = nowSignal:get() + math.max(0, delay), seq = seq, fn = fn, cancelled = false }
		table.insert(scheduled, entry)
		return {
			cancel = function()
				entry.cancelled = true
			end,
		}
	end

	-- advance domain time by `dt` and fire everything that came due, in (at,
	-- seq) order — so two callbacks scheduled for the same instant always run in
	-- the order they were scheduled, which is what makes an arrival sequence
	-- reproducible. A callback that schedules another due callback is picked up
	-- by the same drain (bounded, so a self-rescheduling loop cannot wedge it).
	function self.advance(dt: number): number
		local target = nowSignal:get() + math.max(0, dt or 0)
		nowSignal:set(target)
		local fired = 0
		for _ = 1, 1000 do
			local next_: Scheduled? = nil
			for _, entry in scheduled do
				if entry.cancelled or entry.at > target then
					continue
				end
				if next_ == nil or entry.at < next_.at or (entry.at == next_.at and entry.seq < next_.seq) then
					next_ = entry
				end
			end
			if next_ == nil then
				break
			end
			next_.cancelled = true -- one-shot: mark before running
			fired += 1
			next_.fn()
		end
		-- drop the spent entries so a long session does not grow the list
		local live: { Scheduled } = {}
		for _, entry in scheduled do
			if not entry.cancelled then
				table.insert(live, entry)
			end
		end
		scheduled = live
		return fired
	end

	function self.pendingCount(): number
		local n = 0
		for _, entry in scheduled do
			if not entry.cancelled then
				n += 1
			end
		end
		return n
	end

	function self.dispose()
		scheduled = {}
		nowSignal:dispose()
	end

	return self
end

return table.freeze(clock)
