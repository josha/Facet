--!strict

type ComposeModule = typeof(require("@repo/tools/typecheck/aliases").ComposeModule)

local clock = {}

export type Scheduled = { at: number, seq: number, fn: () -> (), cancelled: boolean }

type ReadOnlyValue<T> = typeof(require("@repo/src/vendor/compose/core").accumulator<<T, number>>(nil :: never))
type Value<T> = typeof(require("@repo/src/vendor/compose/core").cell<<T>>(nil :: never))
export type Handle = { cancel: () -> () }
export type Clock = {
	nowSignal: Value<number>,
	now: () -> number,
	after: (delay: number, fn: () -> ()) -> Handle,
	advance: (dt: number) -> number,
	pendingCount: () -> number,
	dispose: () -> (),
}

function clock.new(Compose: ComposeModule, opts: { start: number? }?): Clock
	local options: { start: number? } = opts or {}
	local nowSignal: Value<number> = Compose.cell(options.start or 0)
	local scheduled: { Scheduled } = {}
	local seq = 0
	local self = { nowSignal = nowSignal }

	function self.now(): number
		return nowSignal:peek()
	end

	function self.after(delay: number, fn: () -> ()): Handle
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
