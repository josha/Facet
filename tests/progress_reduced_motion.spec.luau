--!strict
--[[
	REDUCED MOTION STEPS THE INDETERMINATE INDICATOR. IT NEVER FREEZES IT.

	Everything else this framework animates is decoration: under reduced motion
	it snaps to the end state and nothing is lost, because the information was in
	the end state all along. A loading indicator is the one exception, and it is
	the opposite decision. It is the ONLY thing on the screen saying "work is
	still happening", it has no end state to snap to, and a frozen spinner and a
	hung process look identical. So it takes `src/motion/motion.luau`'s
	INFORMATIONAL policy: the cycle keeps running to the same wall clock and only
	its writes quantize, onto the 250 ms tick. Four steps a second instead of
	sixty. Nothing is skipped — skipping is how reduced motion deletes
	information.

	A port regression replaced that with `timeline:pause(); timeline:seek(0)`,
	deleted the five cases that proved it, and re-pinned three others onto the
	freeze. These are those cases, re-expressed against the native Compose
	timeline that now drives the cycle. Each keeps the ORIGINAL two-beat shape,
	which is what makes them fail a freeze as well as a sixty-a-second sweep:

	  (1) a SUB-QUANTUM step writes nothing — that is quantization, not a stall;
	  (2) the very next step PAST the tick moves it — that is the half a freeze
	      passes and a frozen indicator cannot.

	A case that asserts only (1) is the trap this file exists to close: the
	circular spec's "rests at its start pose" sampled once after a FULL cycle,
	where the sawtooth has wrapped back to its own start pose, and read the
	coincidence as a contract.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local nativeWorld = require("./lib/world")
local progress_view = require("../src/controls/progress_view")

local QUANTUM = progress_view.REDUCED_QUANTUM_S

local function busyWorld(presentation: string?, reduced: boolean?)
	local w = nativeWorld.new({
		viewport = { x = 0, y = 0, w = 400, h = 600 },
		safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
		reducedMotion = reduced,
	})
	w.present(function()
		return w.UI.Screen("S")({
			w.UI.ProgressView("Load")({ presentation = presentation }),
		})
	end)
	expect(#w.handle.controller.diagnostics()).toBe(0)
	return w
end

-- the three presentations, each read off the node the phase actually drives
local READERS: { [string]: (w: any) -> string } = {
	bar = function(w: any): string
		return string.format("%.4f", w.adapter.node("/S/Load/Bar/Sweep/Fill").rect.x)
	end,
	circular = function(w: any): string
		local points = w.adapter.node("/S/Load/Ring/Arc").props.points
		return string.format("%.5f,%.5f", points[1].x, points[1].y)
	end,
	spinner = function(w: any): string
		local parts: { string } = {}
		for index = 1, 5 do
			table.insert(parts, string.format("%.4f", w.adapter.node(`/S/Load/Spinner/Dot{index}`).props.tint.blend))
		end
		return table.concat(parts, ",")
	end,
}

local PRESENTATIONS = { "bar", "circular", "spinner" }

local function distinctReadings(w: any, read: (any) -> string, steps: number, dt: number): number
	local seen: { [string]: boolean } = {}
	local count = 0
	for _ = 1, steps do
		w.frame(dt)
		local key = read(w)
		if seen[key] == nil then
			seen[key] = true
			count += 1
		end
	end
	return count
end

describe("reduced motion keeps the indicator advancing — quantized, never frozen", function()
	for _, presentation in PRESENTATIONS do
		it(`{presentation}: a sub-quantum step writes nothing, and the next tick DOES move it`, function()
			local w = busyWorld(presentation, true)
			local read = READERS[presentation]
			local start = read(w)
			-- inside the tick: the stepped policy, not a stall
			w.frame(QUANTUM / 5)
			expect(read(w)).toBe(start)
			w.frame(QUANTUM / 5)
			expect(read(w)).toBe(start)
			--[[ ...and across it. THIS is the assertion the whole decision rests
				on: reduced motion must not delete the only thing on screen saying
				work is still happening. ]]
			w.frame(QUANTUM)
			expect(read(w) ~= start).toBe(true)
			w.close()
		end)

		it(`{presentation}: over a full cycle it traverses the track in VISIBLE steps`, function()
			local w = busyWorld(presentation, true)
			-- roughly one distinct pose per 250 ms tick over a 1 s cycle: several,
			-- and nothing like the sixty a full-motion second would produce
			local count = distinctReadings(w, READERS[presentation], 20, 0.05)
			expect(count >= 3).toBe(true)
			expect(count <= 8).toBe(true)
			w.close()
		end)

		it(`{presentation}: FULL motion writes far more often over the same wall clock`, function()
			--[[ The differential the two policies are ABOUT, MEASURED rather than
				asserted — and measured in the same process, in the same case, so a
				change that made both arms coarse passes nothing. ]]
			local full = busyWorld(presentation, false)
			local fullCount = distinctReadings(full, READERS[presentation], 20, 0.02)
			full.close()
			local reduced = busyWorld(presentation, true)
			local reducedCount = distinctReadings(reduced, READERS[presentation], 20, 0.02)
			reduced.close()
			expect(fullCount > reducedCount).toBe(true)
			-- still moving: NOT a freeze
			expect(reducedCount >= 2).toBe(true)
		end)
	end
end)

describe("the indeterminate view reports its own state honestly", function()
	it("says it is animating under reduced motion, because it IS", function()
		--[[ The freeze made this field a lie: `animating` stayed true while the
			phase was pinned at 0, which is precisely the "frozen spinner reports
			itself as running" shape the original header warned about. It is true
			here because the indicator really is advancing. ]]
		local w = busyWorld("spinner", true)
		local dump = w.record("Load").dump()
		expect(dump.indeterminate).toBe(true)
		expect(dump.animating).toBe(true)
		expect(dump.semanticText).toBe("Loading")
		w.frame(QUANTUM * 1.5)
		expect(w.record("Load").dump().phase > 0).toBe(true)
		w.close()
	end)

	it("switching policy mid-cycle steps the indicator, never restarts it", function()
		--[[ The freeze's other cost: `seek(0)` threw the cycle back to its
			beginning, so turning reduced motion ON mid-load made the indicator
			jump backwards. Quantizing the READ leaves the clock alone, so the
			indicator lands on the step it had already reached. ]]
		local w = busyWorld("bar", false)
		w.frame(0.6)
		local before = w.record("Load").dump().phase
		expect(before > 0.5).toBe(true)
		w.env:set("reducedMotion", true)
		w.frame(0)
		local after = w.record("Load").dump().phase
		expect(after > 0).toBe(true)
		expect(after <= before).toBe(true)
		expect(before - after < QUANTUM).toBe(true)
		w.close()
	end)

	it("the DETERMINATE path starts no cycle at all, under either policy", function()
		--[[ Without this half, dropping `indeterminate and` from the cycle's
			condition passes everything above. ]]
		local w = nativeWorld.new({
			viewport = { x = 0, y = 0, w = 400, h = 600 },
			safeInsets = { top = 0, bottom = 0, left = 0, right = 0 },
			reducedMotion = true,
		})
		w.present(function()
			return w.UI.Screen("S")({ w.UI.ProgressView("Load")({ value = 0.4 }) })
		end)
		local dump = w.record("Load").dump()
		expect(dump.indeterminate).toBe(false)
		expect(dump.animating).toBeNil()
		expect(dump.fraction).toBe(0.4)
		w.close()
	end)
end)
