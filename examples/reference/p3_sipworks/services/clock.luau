--!strict
-- The injected clock every Sipworks service shares (responsibility ledger:
-- "pure Luau, injectable clock/seed ... no wall-clock in domain logic").
--
-- It reads no time and owns no connection: something outside advances it, and
-- in this proof that something is `presenter.onTick` — the framework's own
-- sanctioned frame source — so the SAME code path runs a scripted `dt` in the
-- headless suite and a real frame delta in Studio, and neither one ever calls
-- `os.clock`.
--
-- Due callbacks fire in time order, and a callback may schedule another (an
-- order's confirm schedules its ready flip): `advance` drains until nothing is
-- due, so one long frame delivers the whole chain in the right order.

local fakeclock = {}

export type Entry = { at: number, run: () -> (), tag: string, cancelled: boolean }

function fakeclock.new(startAt: number?)
	local self = {}
	local t = startAt or 0
	local entries: { Entry } = {}
	local seq = 0

	function self.now(): number
		return t
	end

	-- after(seconds, run, tag) -> a handle whose `cancel()` is idempotent
	function self.after(seconds: number, run: () -> (), tag: string?): { cancel: () -> () }
		seq += 1
		local entry: Entry = { at = t + math.max(0, seconds), run = run, tag = tag or ("t" .. seq), cancelled = false }
		table.insert(entries, entry)
		return {
			cancel = function()
				entry.cancelled = true
			end,
		}
	end

	local function takeDue(): Entry?
		local best: Entry? = nil
		local bestIndex = 0
		for i, entry in entries do
			if entry.cancelled then
				continue
			end
			if entry.at <= t and (best == nil or entry.at < (best :: Entry).at) then
				best, bestIndex = entry, i
			end
		end
		if best ~= nil then
			table.remove(entries, bestIndex)
		end
		return best
	end

	function self.advance(dt: number)
		t += math.max(0, dt or 0)
		-- a bounded drain: a callback may schedule the next beat, and a runaway
		-- scheduler must not wedge a frame
		for _ = 1, 64 do
			local entry = takeDue()
			if entry == nil then
				break
			end
			entry.run()
		end
		-- drop anything cancelled while we were draining
		for i = #entries, 1, -1 do
			if entries[i].cancelled then
				table.remove(entries, i)
			end
		end
	end

	function self.pending(): number
		local n = 0
		for _, entry in entries do
			if not entry.cancelled then
				n += 1
			end
		end
		return n
	end

	function self.reset(startFrom: number?)
		t = startFrom or 0
		table.clear(entries)
	end

	return self
end

return fakeclock
