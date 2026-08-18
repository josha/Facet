--!strict
--[[ THE THREE PROCESS-GLOBAL STORES, AND WHO OWNS THEM
	(architecture review ARCH-23 / ARCH-24).

	`src/layout/text_metrics.luau` holds two mutable module-level tables — the
	per-font engine `calibration` and the measured-`exactWidths` cache — in a
	module its own header calls pure. `src/motion/classes.luau` and
	`src/motion/curves.luau` hold registries that `registerClass`/`registerCurve`
	write. All three are shared by every core and every surface in the VM, and the
	review's question is the right one: what happens when two independent Facet
	consumers run in one place?

	THE ANSWER IS DIFFERENT FOR THE TWO FAMILIES, and that is why this file exists
	rather than a blanket "scope it per core".

	TEXT METRICS ARE CONTENT-ADDRESSED, so sharing them is not a coupling — it is
	a cache hit. The key is `(canonical font, size, word)` and the value is what
	the ENGINE answers for exactly that triple; nothing about which core asked can
	change it. Two cores measuring "Ready" in Gotham 18 must get the same number
	or one of them is wrong. Per-core scoping would not remove a hazard here, it
	would remove the sharing that makes the second surface free, and it would
	double the engine round trips that
	`docs/lessons/roblox-text-bounds-boot-window.md` exists because of. Both
	stores already have reset seams (`resetCalibration`, `resetMeasured`); what
	they lacked was a stated owner, which is now in each module's header.

	THE MOTION REGISTRIES ARE SHARED ON PURPOSE, and the sharing is the API. A
	motion class is a design-system decision — `classes.luau`'s own header: "the
	registry is the only dial" — and re-registering a name is the sanctioned way
	to tune it. Two consumers in one VM therefore share a vocabulary, and the
	third case below pins exactly what that means so nobody has to discover it.
	This is the residual the reuse ledger records rather than a defect this wave
	fixes: making the registry per-core would change the shape of
	`Facet.motion.registerClass`, which is a public break on a compatible-minor
	wave, and it would make the tuning dial stop working across surfaces, which is
	the behaviour the dial was built for.
]]

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local customCore = require("../src/core/custom")
local textMetrics = require("../src/layout/text_metrics")
local Facet = require("../src") :: any

describe("ARCH-23: the text-metric stores are content-addressed, not core-owned", function()
	it("a width measured under one core is the same answer under another", function()
		textMetrics.resetMeasured()
		local a = customCore.new()
		local b = customCore.new()
		expect(a ~= b).toBe(true)

		-- core A measures
		textMetrics.setMeasured("GothamSSm", 18, "Ready", 47)
		--[[ THE KEY IS THE WHOLE INPUT. Nothing about WHICH core asked is in it,
			because nothing about which core asked can change what the engine answers
			for that font, that size and that word. A second surface reading this is a
			cache hit, not a leak across an ownership boundary. ]]
		expect(textMetrics.measuredWidth("GothamSSm", 18, "Ready")).toBe(47)
		expect(textMetrics.measuredWidth("GothamSSm", 20, "Ready")).toBeNil() -- size is part of it
		expect(textMetrics.measuredWidth("GothamSSm", 18, "Steady")).toBeNil() -- so is the word
		textMetrics.resetMeasured()
		expect(textMetrics.measuredWidth("GothamSSm", 18, "Ready")).toBeNil()
	end)

	it("calibration is per-FONT and clamps, so a bad measurement cannot corrupt a good one", function()
		textMetrics.resetCalibration()
		textMetrics.calibrate("GothamSSm", 0.48)
		textMetrics.calibrate("BuilderSans", 0.44)
		local table1 = textMetrics.calibrationTable()
		expect(table1.GothamSSm).toBe(0.48)
		expect(table1.BuilderSans).toBe(0.44)

		--[[ THE SEAM ENFORCES SAFETY, NOT THE CALLER (the module's own rule): a
			calibration may only TIGHTEN toward the proven-safe default and may never
			collapse below the floor. So the worst a second consumer can do to a
			first is hand in a number that gets clamped — never one that causes
			under-reservation. ]]
		textMetrics.calibrate("GothamSSm", 0.99)
		textMetrics.calibrate("BuilderSans", -5)
		local table2 = textMetrics.calibrationTable()
		expect(table2.GothamSSm <= 0.62).toBe(true)
		expect(table2.BuilderSans >= 0.30).toBe(true)
		-- ...and a non-number is ignored outright rather than stored
		textMetrics.calibrate("GothamSSm", 0 / 0)
		expect(textMetrics.calibrationTable().GothamSSm).toBe(table2.GothamSSm)
		textMetrics.resetCalibration()
		expect(next(textMetrics.calibrationTable())).toBeNil()
	end)
end)

describe("ARCH-24: the motion registries are shared, and that is the dial", function()
	--[[ THE COUPLING, WRITTEN DOWN. Not asserted as safe — asserted as REAL, so
		the next author reads the consequence here instead of finding it. ]]
	it("two cores see one motion vocabulary, because a class is a design decision", function()
		Facet.motion.resetClasses()
		local a = customCore.new()
		local b = customCore.new()
		Facet.motion.registerClass("arch24", { dampingRatio = 1, response = 0.3 })

		-- core B never registered anything and can resolve it
		expect(Facet.motion.isRegisteredClass("arch24")).toBe(true)
		expect(Facet.motion.resolveClass("arch24").response).toBe(0.3)

		--[[ AND RE-REGISTERING IS THE TUNING DIAL, not a collision to be refused:
			`classes.luau` states it — "re-registering a built-in name is the
			sanctioned way to tune one: the registry is the only dial". Two consumers
			that pick the same NAME for different feels will therefore agree with
			whoever registered last, which is the residual the reuse ledger records:
			removing it means changing the public shape of `registerClass` and
			breaking the dial it was built to be. ]]
		Facet.motion.registerClass("arch24", { dampingRatio = 0.7, response = 0.5 })
		expect(Facet.motion.resolveClass("arch24").response).toBe(0.5)
		expect(a ~= b).toBe(true)

		Facet.motion.resetClasses()
		expect(Facet.motion.isRegisteredClass("arch24")).toBe(false)
	end)

	it("reset restores the built-in classes but leaves the curve registry empty", function()
		Facet.motion.resetClasses()
		Facet.motion.resetCurves()
		--[[ THE ASYMMETRY IS DELIBERATE and is the reason these are two verbs: the
			class registry ships with four built-in physical shapes, so its reset
			RESTORES them, while the curve registry ships EMPTY on purpose (a duration
			is a decision about one surface), so its reset leaves nothing. A single
			`resetMotion` would have to pick one meaning. ]]
		expect(#Facet.motion.classNames() >= 4).toBe(true)
		expect(#Facet.motion.curveNames()).toBe(0)
	end)
end)
