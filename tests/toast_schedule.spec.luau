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
