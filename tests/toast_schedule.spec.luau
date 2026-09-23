--!strict
-- THE TOAST SCHEDULER (acceptance row SF-T2). Every rule
-- here is a timing rule, so every case scripts `now()` — "after 1.5 seconds"
-- means the same thing forever, on every machine.
--
-- The two rules worth stating twice, because they are the ones a naive
-- implementation gets wrong:
--   * priority orders the QUEUE and never truncates a SHOWING toast's read floor
--     (disposition F2) — the urgent thing waits for the sentence to be readable;
--   * a queued toast dropped at the cap emits `dismiss(reason = "capacity")`
--     (disposition F3) — nothing vanishes untraceably.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local toast_schedule = require("../src/present/toast_schedule")

type Fixture = {
	schedule: any,
	advance: (seconds: number) -> (),
	events: { { id: number, key: string?, reason: string } },
	keys: () -> string,
}

local function fixture(opts: any?): Fixture
	local now = 0
	local events: { { id: number, key: string?, reason: string } } = {}
	local options: any = opts or {}
	options.now = function()
		return now
	end
	options.onDismiss = function(entry: any, reason: string)
		table.insert(events, { id = entry.id, key = entry.key, reason = reason })
	end
	local schedule = toast_schedule.new(options)
	return {
		schedule = schedule,
		events = events,
		advance = function(seconds: number)
			now += seconds
			schedule.update()
		end,
		keys = function(): string
			local out: { string } = {}
			for _, entry in schedule.visible() do
				table.insert(out, tostring(entry.data))
			end
			return table.concat(out, ",")
		end,
	}
end

describe("toast schedule: showing, queueing and timing out", function()
	it("shows up to maxVisible and queues the rest, newest last", function()
		local f = fixture()
		for i = 1, 5 do
			f.schedule.push({ data = `t{i}` })
		end
		expect(f.keys()).toBe("t1,t2,t3")
		expect(f.schedule.counts().queued).toBe(2)
	end)

	it("a toast times out after its duration and the queue promotes in that frame", function()
		local f = fixture()
		f.schedule.push({ data = "a", duration = 2 })
		f.schedule.push({ data = "b", duration = 2 })
		f.schedule.push({ data = "c", duration = 2 })
		f.schedule.push({ data = "d", duration = 2 })
		expect(f.keys()).toBe("a,b,c")
		f.advance(1.9)
		expect(f.keys()).toBe("a,b,c")
		f.advance(0.2)
		expect(f.keys()).toBe("d")
		expect(#f.events).toBe(3)
		expect(f.events[1].reason).toBe("timeout")
	end)

	it("durations and read floors are per-toast, not global", function()
		local f = fixture()
		f.schedule.push({ data = "short", duration = 1 })
		f.schedule.push({ data = "long", duration = 6 })
		f.advance(1.5)
		expect(f.keys()).toBe("long")
	end)

	it("the defaults are the ratified numbers", function()
		expect(toast_schedule.DEFAULTS.maxVisible).toBe(3)
		expect(toast_schedule.DEFAULTS.queueCap).toBe(8)
		expect(toast_schedule.DEFAULTS.duration).toBe(4)
		expect(toast_schedule.DEFAULTS.readFloor).toBe(2.5)
	end)
end)

describe("toast schedule: priority", function()
	it("the queue is priority-ordered, FIFO within a priority", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "first", duration = 10 })
		f.schedule.push({ data = "low", priority = 0 })
		f.schedule.push({ data = "high", priority = 5 })
		f.schedule.push({ data = "low2", priority = 0 })
		local queued = f.schedule.queued()
		expect(queued[1].data).toBe("high")
		expect(queued[2].data).toBe("low")
		expect(queued[3].data).toBe("low2")
	end)

	it("a more urgent toast NEVER truncates a showing toast's read floor", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "reading", duration = 10, readFloor = 1.5 })
		f.schedule.push({ data = "urgent", priority = 10 })
		-- the floor is not up: the urgent toast waits, however urgent it is
		f.advance(1.4)
		expect(f.keys()).toBe("reading")
		expect(#f.events).toBe(0)
		-- the moment the floor is met, it takes the slot
		f.advance(0.2)
		expect(f.keys()).toBe("urgent")
		expect(#f.events).toBe(1)
		expect(f.events[1].reason).toBe("preempt")
	end)

	it("preemption takes the WEAKEST showing toast, not the oldest", function()
		local f = fixture({ maxVisible = 2 })
		f.schedule.push({ data = "important", priority = 5, duration = 10 })
		f.schedule.push({ data = "trivial", priority = 0, duration = 10 })
		f.schedule.push({ data = "urgent", priority = 9 })
		f.advance(3) -- past the 2.5 s read floor, so the weakest is preemptable
		expect(f.keys()).toBe("important,urgent")
	end)

	it("a queued toast no more urgent than the weakest showing one just waits", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "showing", priority = 5, duration = 10 })
		f.schedule.push({ data = "same", priority = 5 })
		f.advance(5)
		expect(f.keys()).toBe("showing")
		expect(#f.events).toBe(0)
	end)
end)

describe("toast schedule: supersede and capacity", function()
	it("a same-key toast replaces its QUEUED predecessor immediately", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "hold", duration = 10 })
		f.schedule.push({ data = "lap 1", key = "lap" })
		f.schedule.push({ data = "lap 2", key = "lap" })
		expect(f.schedule.counts().queued).toBe(1)
		expect(f.schedule.queued()[1].data).toBe("lap 2")
		expect(#f.events).toBe(1)
		expect(f.events[1].reason).toBe("supersede")
	end)

	it("a same-key toast replaces a SHOWING one only once its floor is met", function()
		local f = fixture({ maxVisible = 3 })
		f.schedule.push({ data = "lap 1", key = "lap", duration = 10, readFloor = 1.5 })
		f.schedule.push({ data = "lap 2", key = "lap", duration = 10 })
		expect(f.keys()).toBe("lap 1")
		f.advance(1.0)
		expect(f.keys()).toBe("lap 1")
		f.advance(0.6)
		expect(f.keys()).toBe("lap 2")
		expect(f.events[1].reason).toBe("supersede")
	end)

	it("at the queue cap the LOWEST-priority queued toast is dropped, with a reason", function()
		local f = fixture({ maxVisible = 1, queueCap = 3 })
		f.schedule.push({ data = "showing", duration = 10 })
		f.schedule.push({ data = "q1", priority = 3 })
		f.schedule.push({ data = "q2", priority = 2 })
		f.schedule.push({ data = "q3", priority = 1 })
		expect(f.schedule.counts().queued).toBe(3)
		expect(#f.events).toBe(0)
		f.schedule.push({ data = "q4", priority = 4 })
		expect(f.schedule.counts().queued).toBe(3)
		expect(#f.events).toBe(1)
		expect(f.events[1].reason).toBe("capacity")
		local queued = f.schedule.queued()
		expect(queued[1].data).toBe("q4")
		expect(queued[3].data).toBe("q2")
	end)

	it("a newcomer that IS the least urgent thing drops itself, and says so", function()
		local f = fixture({ maxVisible = 1, queueCap = 1 })
		f.schedule.push({ data = "showing", duration = 10 })
		f.schedule.push({ data = "kept", priority = 5 })
		f.schedule.push({ data = "dropped", priority = 1 })
		expect(f.schedule.queued()[1].data).toBe("kept")
		expect(#f.events).toBe(1)
		expect(f.events[1].reason).toBe("capacity")
	end)

	it("a SHOWING toast is never dropped for capacity", function()
		local f = fixture({ maxVisible = 2, queueCap = 1 })
		f.schedule.push({ data = "a", duration = 10 })
		f.schedule.push({ data = "b", duration = 10 })
		for i = 1, 6 do
			f.schedule.push({ data = `flood{i}`, priority = -1 })
		end
		expect(f.keys()).toBe("a,b")
		for _, event in f.events do
			expect(event.reason).toBe("capacity")
		end
	end)

	it("a burst never stacks unbounded", function()
		local f = fixture()
		for i = 1, 200 do
			f.schedule.push({ data = `spam{i}` })
		end
		local counts = f.schedule.counts()
		expect(counts.visible).toBe(3)
		expect(counts.queued).toBe(8)
	end)
end)

describe("toast schedule: explicit dismissal", function()
	it("dismiss retires a showing toast and promotes the queue in the same call", function()
		local f = fixture({ maxVisible = 1 })
		local id = f.schedule.push({ data = "a", duration = 10 })
		f.schedule.push({ data = "b", duration = 10 })
		expect(f.schedule.dismiss(id)).toBe(true)
		expect(f.keys()).toBe("b")
		expect(f.events[1].reason).toBe("manual")
	end)

	it("dismiss finds a QUEUED toast too, and an unknown id is a false, not an error", function()
		local f = fixture({ maxVisible = 1 })
		f.schedule.push({ data = "a", duration = 10 })
		local queued = f.schedule.push({ data = "b" })
		expect(f.schedule.dismiss(queued)).toBe(true)
		expect(f.schedule.counts().queued).toBe(0)
		expect(f.schedule.dismiss(9999)).toBe(false)
	end)

	it("clear retires everything, each with its reason", function()
		local f = fixture({ maxVisible = 2 })
		f.schedule.push({ data = "a", duration = 10 })
		f.schedule.push({ data = "b", duration = 10 })
		f.schedule.push({ data = "c", duration = 10 })
		f.schedule.clear("teardown")
		expect(f.schedule.isEmpty()).toBe(true)
		expect(#f.events).toBe(3)
		for _, event in f.events do
			expect(event.reason).toBe("teardown")
		end
	end)
end)

--[[ THE CONTROLLED SEAM (opt-in; Snackbar). The caller owns visibility: a
	visible entry is removed for a timeout or a supersession only after its
	`request` accepts, one request per reason per entry; `nil` duration is
	persistent; the dwell is the caller's `elapsed` and never ends below the read
	floor; admission beyond the cap is refused, never dropped; and callbacks may
	re-enter push/dismiss/clear. The Toast defaults above are untouched. ]]
local function controlled(extra: any?): any
	local now = 0
	local log = { requests = {}, dismissed = {} }
	local opts: any = {
		controlled = true,
		maxVisible = 1,
		queueCap = 8,
		now = function()
			return now
		end,
		onDismiss = function(entry: any, reason: string)
			table.insert(log.dismissed, `{entry.data}:{reason}`)
		end,
	}
	for k, v in extra or {} do
		opts[k] = v
	end
	local schedule = toast_schedule.new(opts)
	return {
		schedule = schedule,
		log = log,
		advance = function(seconds: number)
			now += seconds
			schedule.update()
		end,
		shown = function(): string
			local out = {}
			for _, e in schedule.visible() do
				table.insert(out, tostring(e.data))
			end
			return table.concat(out, ",")
		end,
	}
end

describe("toast schedule: the controlled seam", function()
	it("a refused timeout keeps the entry and is asked once", function()
		local accept = false
		local f
		f = controlled({
			request = function(entry: any, reason: string): boolean
				table.insert(f.log.requests, `{entry.data}:{reason}`)
				return accept
			end,
		})
		f.schedule.push({ data = "a", duration = 1 })
		f.advance(2.4)
		expect(#f.log.requests).toBe(0) -- the read floor, not the 1 s duration
		f.advance(0.2)
		expect(f.log.requests).toEqual({ "a:timeout" })
		expect(f.shown()).toBe("a")
		f.advance(10)
		expect(f.log.requests).toEqual({ "a:timeout" }) -- consumed
		expect(f.shown()).toBe("a")
		expect(#f.log.dismissed).toBe(0)
	end)

	it(
		"an accepted timeout retires once, and a caller who dismisses inside the request is not double-reported",
		function()
			local f
			f = controlled({
				request = function(entry: any, reason: string): boolean
					table.insert(f.log.requests, `{entry.data}:{reason}`)
					if entry.data == "b" then
						f.schedule.dismiss(entry.id, reason) -- the caller's false lands synchronously
					end
					return true
				end,
			})
			f.schedule.push({ data = "a", duration = 3 })
			f.schedule.push({ data = "b", duration = 3 })
			f.advance(3)
			expect(f.log.dismissed).toEqual({ "a:timeout" })
			expect(f.shown()).toBe("b")
			f.advance(3)
			expect(f.log.dismissed).toEqual({ "a:timeout", "b:timeout" })
			expect(f.shown()).toBe("")
		end
	)

	it("nil duration is persistent; the caller's elapsed pauses the dwell", function()
		local paused = 0
		local f = controlled({
			request = function()
				return true
			end,
			elapsed = function(entry: any, t: number): number
				return t - entry.shownAt - paused
			end,
		})
		f.schedule.push({ data = "p" })
		f.advance(1000)
		expect(f.shown()).toBe("p")
		f.schedule.dismiss(f.schedule.visible()[1].id, "close")
		f.schedule.push({ data = "q", duration = 4 })
		f.advance(3)
		paused = 2 -- two of those seconds were covered
		f.advance(0.5)
		expect(f.shown()).toBe("q")
		f.advance(2.5)
		expect(f.shown()).toBe("")
	end)

	it("supersession waits for the floor, asks once, and a refusal keeps every contender queued", function()
		local answer = false
		local asked = 0
		local f = controlled({
			request = function(_entry: any, reason: string): boolean
				expect(reason).toBe("preempt")
				asked += 1
				return answer
			end,
		})
		f.schedule.push({ data = "low", priority = 0 })
		f.schedule.push({ data = "same", priority = 0 })
		f.schedule.push({ data = "high", priority = 5 })
		f.advance(1)
		expect(asked).toBe(0) -- equal priority waits; higher waits for the floor
		f.advance(1.6)
		expect(asked).toBe(1)
		expect(f.shown()).toBe("low")
		f.schedule.push({ data = "higher", priority = 9 })
		f.advance(5)
		expect(asked).toBe(1) -- no spam on ticks or arrivals
		f.schedule.dismiss(f.schedule.visible()[1].id, "close")
		expect(f.shown()).toBe("higher")
		answer = true
		f.advance(2.6)
		expect(f.shown()).toBe("higher") -- nothing queued outranks it
		f.schedule.push({ data = "urgent", priority = 12 })
		f.advance(0.1)
		expect(f.shown()).toBe("urgent")
		expect(f.log.dismissed).toEqual({ "low:close", "higher:preempt" })
	end)

	it("admission past the cap is refused atomically; capacity frees on removal", function()
		local f = controlled({
			queueCap = 2,
			request = function()
				return true
			end,
		})
		expect(f.schedule.push({ data = "1" }) ~= nil).toBe(true)
		expect(f.schedule.push({ data = "2" }) ~= nil).toBe(true)
		expect(f.schedule.push({ data = "3" }) ~= nil).toBe(true)
		expect(f.schedule.push({ data = "4" })).toBeNil()
		expect(f.schedule.counts()).toEqual({ visible = 1, queued = 2, sequence = 3 })
		expect(#f.log.dismissed).toBe(0)
		f.schedule.dismiss(f.schedule.visible()[1].id, "close")
		expect(f.schedule.push({ data = "4" }) ~= nil).toBe(true)
	end)

	it("the caller's identity is published before any callback runs", function()
		local seen = {}
		local f
		f = controlled({
			onChange = function()
				for _, e in f.schedule.visible() do
					table.insert(seen, e.id)
				end
			end,
			request = function()
				return true
			end,
		})
		f.schedule.push({ id = "row-7", data = "x" })
		expect(seen).toEqual({ "row-7" })
		expect(f.schedule.dismiss("row-7", "close")).toBe(true)
	end)

	it("callbacks may push, dismiss, clear or throw without a stale index", function()
		local f
		local depth = 0
		f = controlled({
			request = function(entry: any): boolean
				depth += 1
				if entry.data == "a" then
					f.schedule.push({ data = "late", duration = 3 }) -- enqueue inside a request
					f.schedule.dismiss(entry.id, "timeout")
				elseif entry.data == "late" then
					f.schedule.clear("teardown") -- clear inside a request
				end
				return true
			end,
			onDismiss = function(entry: any, reason: string)
				table.insert(f.log.dismissed, `{entry.data}:{reason}`)
				if entry.data == "b" then
					error("caller bug")
				end
			end,
		})
		f.schedule.push({ data = "a", duration = 3 })
		f.schedule.push({ data = "b", duration = 3 })
		f.advance(3)
		expect(f.shown()).toBe("b")
		expect(pcall(function()
			f.schedule.dismiss(f.schedule.visible()[1].id, "close")
		end)).toBe(false) -- the throw reaches the caller...
		expect(f.shown()).toBe("late") -- ...after the schedule is consistent
		f.advance(3)
		expect(f.schedule.isEmpty()).toBe(true)
		expect(depth >= 2).toBe(true)
	end)

	it("the default (uncontrolled) paths are unchanged", function()
		local f = fixture()
		f.schedule.push({ data = "t", duration = 1 })
		f.advance(1)
		expect(f.keys()).toBe("") -- still expires at its own duration, below the floor
		expect(f.events[1].reason).toBe("timeout")
	end)
end)
