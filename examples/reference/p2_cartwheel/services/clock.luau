--!strict

local clock = {}

export type Scheduled = { at: number, seq: number, fn: () -> (), cancelled: boolean }

function clock.new(Compose: any, opts: { start: number? }?): any
	local options = opts or {}
	local nowSignal = Compose.cell(options.start or 0)
	local scheduled: { Scheduled } = {}
	local seq = 0
	local self: any = { nowSignal = nowSignal }

	function self.now(): number
		return nowSignal:peek()
	end

	function self.after(delay: number, fn: () -> ()): any
		seq += 1
		local entry: Scheduled = { at = nowSignal:peek() + math.max(0, delay), seq = seq, fn = fn, cancelled = false }
		table.insert(scheduled, entry)
		return {
			cancel = function()
				entry.cancelled = true
			end,
		}
	end

	function self.advance(dt: number): number
		local target = nowSignal:peek() + math.max(0, dt or 0)
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
			next_.cancelled = true
			fired += 1
			next_.fn()
		end

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
	end

	return self
end

return table.freeze(clock)
