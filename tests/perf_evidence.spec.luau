--!strict
-- Evidence-class discipline (roadmap Step 4, ledger rows XP-A1/XP-A4/XP-A7).
--
-- This spec exists for one failure mode: a fast desktop number quietly becoming
-- a phone claim. The whole stage is built so that cannot happen by accident, and
-- these cases are the executable half of that promise —
--
--   * every performance record carries exactly one evidence class, and a Lune
--     process may only ever emit the headless one;
--   * a metric the instrument cannot see is an explicit `blind` marker, never an
--     absent field (an absent field reads as zero, and zero reads as free);
--   * checkBudgets REFUSES to enforce a device budget against a report with no
--     rows of that device's class, and reports the refusal as a violation
--     rather than a pass;
--   * an unmeasured device budget is skipped LOUDLY, in the record;
--   * the console/ten-foot profile is in the matrix and really applies the
--     ten-foot facts, so a TV-only regression has somewhere to show up.

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local perf_runner = require("../bench/perf_runner")
local perf_profiles = require("../bench/perf_profiles")
local environment = require("../src/env/environment")
local custom = require("../src/core/custom")

local function tinyScene(name: string?)
	return {
		name = name or "tiny",
		requirement = "UI-PERF-001",
		dataset = "1 signal; 3 writes per iteration",
		setup = function(_profile: any)
			local core = custom.new()
			local s = core:signal(0)
			return { core = core, s = s, n = 0 }
		end,
		run = function(state: any): { [string]: number }?
			state.n += 1
			for i = 1, 3 do
				state.s:set(state.n * 3 + i)
			end
			return nil
		end,
	}
end

describe("evidence classes (UI-PERF-002)", function()
	it("every record carries exactly one evidence class, and Lune may only emit the headless one", function()
		local profile = perf_profiles.get(perf_profiles.REFERENCE)
		local rec = perf_runner.runScene(tinyScene(), profile, { warmup = 1, samples = 3 })
		expect(rec.evidenceClass).toBe("lune")
		expect(rec.evidenceLevel).toBe("E1")
		-- there is no argument a caller can pass that makes this a device run
		expect(perf_runner.CLASS).toBe("lune")
		expect(perf_runner.DEVICE_CLASSES.lune).toBe(nil)
		expect(perf_runner.DEVICE_CLASSES["phone-physical"]).toBe(true)
	end)

	it("declares every class in the inventory, including the ones with zero rows", function()
		local rep = perf_runner.run({ tinyScene("a") }, { perf_profiles.get("desktop") }, { warmup = 1, samples = 2 })
		local byId: { [string]: any } = {}
		for _, c in rep.evidenceClasses do
			byId[c.id] = c
		end
		expect(byId.lune.rows).toBe(1)
		-- absence is STATED: the physical classes appear with zero rows rather
		-- than being missing, so a reader never has to infer what was not run
		expect(byId["phone-physical"].rows).toBe(0)
		expect(byId["console-physical"].rows).toBe(0)
		expect(byId["desktop-retail"].rows).toBe(0)
		expect(type(byId["phone-physical"].cannotProve)).toBe("string")
	end)

	it("a metric the instrument cannot see is a blind marker with a reason, not a zero", function()
		local rec =
			perf_runner.runScene(tinyScene(), perf_profiles.get(perf_profiles.REFERENCE), { warmup = 1, samples = 3 })
		-- M1: a headless process renders no frame
		expect(rec.metrics.frameWorkMs.measured).toBe(false)
		expect(#rec.metrics.frameWorkMs.reason > 0).toBe(true)
		-- M6: this scene drives no input
		expect(rec.metrics.inputToVisibleMs.measured).toBe(false)
		-- M7: this scene swaps no theme
		expect(rec.metrics.themeSwap.measured).toBe(false)
		-- M2/M5 are always real
		expect(rec.metrics.updateMs.measured).toBe(true)
		expect(rec.metrics.memoryKb.measured).toBe(true)
	end)

	it("lifts a scene-declared inputToVisible phase into the M6 slot", function()
		local scene = tinyScene("driven")
		scene.run = function(state: any): { [string]: number }?
			state.n += 1
			local t0 = os.clock()
			state.s:set(state.n)
			return { inputToVisible = os.clock() - t0 }
		end
		local rec = perf_runner.runScene(scene, perf_profiles.get("desktop"), { warmup = 1, samples = 3 })
		expect(rec.metrics.inputToVisibleMs.measured).toBe(true)
		expect(rec.metrics.inputToVisibleMs.p95_ms).toBeGreaterThanOrEqual(0)
		-- and it says what it is NOT: this is never display latency
		expect(string.find(rec.metrics.inputToVisibleMs.note, "no frame", 1, true) ~= nil).toBe(true)
	end)
end)

describe("device budgets are unreachable from the wrong class (UI-PERF-002)", function()
	local function headlessReport()
		return {
			schema = "luauui-perf/2",
			environment = { evidenceClass = "lune" },
			referenceProfile = "floorAndroid",
			runs = {
				{
					scene = "hud-binding-storm",
					device = "floorAndroid",
					evidenceClass = "lune",
					requirement = "UI-PERF-001",
					phases = { total = { p50_ms = 0.1, p95_ms = 0.2, p99_ms = 0.3 } },
					metrics = { frameWorkMs = { measured = false, reason = "headless" } },
				},
			},
		}
	end

	it("refuses to enforce a device budget from a non-device class", function()
		local budgets = {
			referenceProfile = "floorAndroid",
			scenes = {},
			deviceBudgets = {
				["phone-physical"] = { budgetMs = 8.33, measured = true, requirement = "UI-PERF-002" },
			},
		}
		local result = perf_runner.checkBudgets(headlessReport(), budgets)
		expect(result.ok).toBe(false)
		expect(#result.violations).toBe(1)
		expect(result.violations[1].kind).toBe("class-mismatch")
		expect(result.violations[1].device).toBe("phone-physical")
		-- the hint must say WHY, in words a reader who did not write this can act on
		expect(string.find(result.violations[1].hint, "no rows of", 1, true) ~= nil).toBe(true)
	end)

	it("skips an unmeasured device budget LOUDLY rather than silently passing it", function()
		local budgets = {
			referenceProfile = "floorAndroid",
			scenes = {},
			deviceBudgets = {
				["console-physical"] = { budgetMs = 4.17, measured = false },
			},
		}
		local result = perf_runner.checkBudgets(headlessReport(), budgets)
		expect(result.ok).toBe(true)
		expect(#result.skipped).toBe(1)
		expect(result.skipped[1].class).toBe("console-physical")
		expect(string.find(result.skipped[1].reason, "PENDING_PHYSICAL", 1, true) ~= nil).toBe(true)
	end)

	it("a device-class row with no measured frame work does not satisfy its budget", function()
		-- the hole the fresh-context audit found: the refusal guarded the class
		-- STRING, so a row that merely claimed to be a phone — carrying no
		-- measurement at all — satisfied a phone budget of 0.001ms.
		local rep = headlessReport()
		table.insert(rep.runs, {
			scene = "hud-binding-storm",
			device = "pixel-4a",
			evidenceClass = "phone-physical",
			requirement = "UI-PERF-002",
			phases = { total = { p50_ms = 1, p95_ms = 2, p99_ms = 3 } },
			-- no metrics block at all
		})
		local result = perf_runner.checkBudgets(rep, {
			referenceProfile = "floorAndroid",
			scenes = {},
			deviceBudgets = {
				["phone-physical"] = { budgetMs = 0.001, measured = true, requirement = "UI-PERF-002" },
			},
		})
		expect(result.ok).toBe(false)
		expect(result.violations[1].kind).toBe("unmeasured-device-row")
		expect(string.find(result.violations[1].hint, "not by an evidence-class", 1, true) ~= nil).toBe(true)
	end)

	it("a device row whose frame work is blind does not error the budget check", function()
		-- and the same path used to THROW on the honest case: `measured = false`
		-- made the guard compare a number against a boolean
		local rep = headlessReport()
		table.insert(rep.runs, {
			scene = "dense-hud",
			device = "pixel-4a",
			evidenceClass = "phone-physical",
			requirement = "UI-PERF-002",
			phases = { total = { p50_ms = 1, p95_ms = 2, p99_ms = 3 } },
			metrics = { frameWorkMs = { measured = false, reason = "the capture tool could not read frame time" } },
		})
		local ok, result = pcall(perf_runner.checkBudgets, rep, {
			referenceProfile = "floorAndroid",
			scenes = {},
			deviceBudgets = {
				["phone-physical"] = { budgetMs = 8.33, measured = true, requirement = "UI-PERF-002" },
			},
		})
		expect(ok).toBe(true)
		expect(result.ok).toBe(false)
		expect(result.violations[1].kind).toBe("unmeasured-device-row")
	end)

	it("a NaN or negative frame time is not a measurement", function()
		for _, bad in { 0 / 0, -1 } do
			local rep = headlessReport()
			table.insert(rep.runs, {
				scene = "dense-hud",
				device = "pixel-4a",
				evidenceClass = "phone-physical",
				phases = { total = { p50_ms = 1, p95_ms = 2, p99_ms = 3 } },
				metrics = { frameWorkMs = { measured = true, p95_ms = bad } },
			})
			local result = perf_runner.checkBudgets(rep, {
				referenceProfile = "floorAndroid",
				scenes = {},
				deviceBudgets = { ["phone-physical"] = { budgetMs = 8.33, measured = true } },
			})
			expect(result.ok).toBe(false)
			expect(result.violations[1].kind).toBe("unmeasured-device-row")
		end
	end)

	it("refuses without throwing on a hand-authored report that has no environment block", function()
		-- the review packet asks a reviewer to author a device capture by hand;
		-- the refusal used to crash on the shape they would produce
		local ok, result = pcall(perf_runner.checkBudgets, {
			schema = "luauui-perf/2",
			runs = {
				{ scene = "x", device = "floorAndroid", evidenceClass = "lune", phases = { total = { p95_ms = 1 } } },
			},
		}, {
			referenceProfile = "floorAndroid",
			scenes = {},
			deviceBudgets = { ["phone-physical"] = { budgetMs = 8.33, measured = true } },
		})
		expect(ok).toBe(true)
		expect(result.ok).toBe(false)
		expect(result.violations[1].kind).toBe("class-mismatch")
		expect(string.find(result.violations[1].hint, "unstated", 1, true) ~= nil).toBe(true)
	end)

	it("enforces a device budget only against rows of its own class", function()
		local rep = headlessReport()
		table.insert(rep.runs, {
			scene = "hud-binding-storm",
			device = "pixel-4a",
			evidenceClass = "phone-physical",
			requirement = "UI-PERF-002",
			phases = { total = { p50_ms = 1, p95_ms = 2, p99_ms = 3 } },
			metrics = { frameWorkMs = { measured = true, p95_ms = 12.0 } },
		})
		local budgets = {
			referenceProfile = "floorAndroid",
			scenes = {},
			deviceBudgets = {
				["phone-physical"] = { budgetMs = 8.33, measured = true, requirement = "UI-PERF-002" },
			},
		}
		local result = perf_runner.checkBudgets(rep, budgets)
		expect(result.ok).toBe(false)
		expect(result.violations[1].kind).toBe("device")
		expect(result.violations[1].observedMs).toBe(12.0)
		-- and the headless row, which is NOT of that class, contributed nothing
		expect(#result.violations).toBe(1)
	end)
end)

describe("the frame ceiling is one-directional (UI-PERF-002)", function()
	it("derives the ceiling from the frame target and the declared UI share", function()
		-- 30Hz frame is 33.33ms; a quarter of it is 8.33ms
		local ceiling = perf_runner.ceilingMsFor(30, 0.25)
		expect(math.abs(ceiling - 8.3333) < 0.001).toBe(true)
		expect(math.abs(perf_runner.ceilingMsFor(60, 0.25) - 4.1666) < 0.001).toBe(true)
	end)

	it("flags a scene above the ceiling separately from a trend regression", function()
		local rep = {
			schema = "luauui-perf/2",
			environment = { evidenceClass = "lune" },
			runs = {
				{
					scene = "heavy",
					device = "floorAndroid",
					evidenceClass = "lune",
					requirement = "UI-PERF-001",
					phases = { total = { p50_ms = 5, p95_ms = 9.0, p99_ms = 10 } },
				},
			},
		}
		local budgets = {
			referenceProfile = "floorAndroid",
			scenes = {
				-- generous trend budget, so ONLY the ceiling can fire
				heavy = {
					total_p95_ms = 100,
					requirement = "UI-PERF-001",
					ceilingMs = 8.3333,
					frameTargetHz = 30,
					hint = "x",
				},
			},
		}
		local result = perf_runner.checkBudgets(rep, budgets)
		expect(result.ok).toBe(false)
		expect(result.violations[1].kind).toBe("frame-ceiling")
		expect(string.find(result.violations[1].hint, "cannot hold the frame target anywhere", 1, true) ~= nil).toBe(
			true
		)
	end)
end)

describe("console / ten-foot profile (UI-PARADIGM-003, XP-A1)", function()
	it("is in the headless matrix", function()
		local names = perf_profiles.list()
		local found = false
		for _, n in names do
			if n == "consoleTenFoot" then
				found = true
			end
		end
		expect(found).toBe(true)
	end)

	it("applies the ten-foot facts, not just a large viewport", function()
		local core = custom.new()
		local env = environment.new(core)
		local profile = perf_profiles.get("consoleTenFoot")
		perf_profiles.apply(env, profile)
		expect(env:get("displaySize"):get()).toBe("Large")
		expect(env:get("preferredInput"):get()).toBe("Gamepad")
		-- the derived ten-foot policy really engages: type floor and overscan
		expect(env:get("distanceProfile"):get()).toBe("ten-foot")
		expect(env:get("typographyScale"):get()).toBe(1.5)
		expect(env:get("effectiveOverscanInsets"):get().left).toBeGreaterThan(0)
		expect(env:get("interactionClasses"):get().primary).toBe("gamepad")
	end)

	it("declares a frame target for every profile, so a ceiling can be derived", function()
		for _, name in perf_profiles.list() do
			local p = perf_profiles.get(name)
			expect(type(p.frameTargetHz)).toBe("number")
			expect(p.frameTargetHz > 0).toBe(true)
		end
		-- the floor device targets 30Hz; everything else targets 60Hz
		expect(perf_profiles.get("floorAndroid").frameTargetHz).toBe(30)
		expect(perf_profiles.get("consoleTenFoot").frameTargetHz).toBe(60)
	end)
end)

-- ===========================================================================
-- PROVENANCE: a class is a claim, and a claim has to carry something
-- ===========================================================================
--
-- Two fresh-context reviews attacked the device-capture path in a row. The
-- first relabelled the FILE, and ingestion was fixed to key on the row's own
-- class. The second relabelled BOTH — one `sed` over the real Studio capture —
-- so the labels agreed and five host rows satisfied a measured phone budget.
--
-- These cases are the executable form of the answer: a physical row must carry
-- what a Studio session structurally cannot shed, and enough of a measurement
-- to be worth checking a budget against.
describe("physical-row provenance", function()
	local function studioShapedRow(): any
		return {
			evidenceClass = "phone-physical",
			evidenceLevel = "E4",
			identity = { libraryVersion = "0.7.0" },
			provenance = {
				isStudio = false,
				clientKind = "retail",
				instrument = "retail Roblox client, capture scenario perf_capture",
				deviceModel = "SM-A065F",
				capturedAt = "2026-07-26T18:00:00Z",
				attestedBy = "josha",
			},
			device = { live = { source = "retail client on the physical device" } },
			metrics = {
				M1_frameWorkMs = { measured = true, p95_ms = 3.9 },
				M2_updateMs = { measured = true },
				M3_instances = { measured = true },
				M4_connections = { measured = true },
				M5_memory = { measured = true },
				M6_inputToCommittedWrite = { measured = true },
			},
		}
	end

	it("accepts a row that carries everything its class implies", function()
		expect(#perf_runner.provenanceProblems(studioShapedRow())).toBe(0)
	end)

	it("says nothing about a row that is not of a device class", function()
		local row = studioShapedRow()
		row.evidenceClass = "studio-emulated"
		row.identity.studioVersion = "0.731.0.7310942"
		expect(#perf_runner.provenanceProblems(row)).toBe(0)
	end)

	it("refuses a physical row that carries a Studio version", function()
		local row = studioShapedRow()
		row.identity.studioVersion = "0.731.0.7310942"
		local problems = perf_runner.provenanceProblems(row)
		expect(#problems).toBe(1)
		expect(string.find(problems[1], "studioVersion", 1, true) ~= nil).toBe(true)
	end)

	it("refuses a physical row that names a device-simulator preset", function()
		local row = studioShapedRow()
		row.device.live.deviceId = "samsung_galaxy_s22_ultra"
		expect(#perf_runner.provenanceProblems(row)).toBe(1)
	end)

	it("refuses a physical row whose live facts came from the Studio simulator", function()
		local row = studioShapedRow()
		row.device.live.source = "StudioDeviceSimulatorService getters"
		expect(#perf_runner.provenanceProblems(row)).toBe(1)
	end)

	it("refuses the Studio evidence level under a physical class", function()
		local row = studioShapedRow()
		row.evidenceLevel = "E3"
		local problems = perf_runner.provenanceProblems(row)
		expect(#problems).toBe(1)
		expect(string.find(problems[1], "E4", 1, true) ~= nil).toBe(true)
	end)

	it("refuses a hand-written row with one number in it", function()
		local problems = perf_runner.provenanceProblems({
			evidenceClass = "phone-physical",
			evidenceLevel = "E4",
			metrics = { frameWorkMs = { measured = true, p95_ms = 1.2 } },
		})
		-- one problem per absent metric, plus the absent attestation
		expect(#problems >= 5).toBe(true)
	end)

	it("refuses a row that carries no attestation at all", function()
		local row = studioShapedRow()
		row.provenance = nil
		local problems = perf_runner.provenanceProblems(row)
		expect(#problems).toBe(1)
		expect(string.find(problems[1], "provenance", 1, true) ~= nil).toBe(true)
	end)

	it("refuses an attestation with a field renamed rather than written", function()
		-- THE ROUND-5 ATTACK, from the other side. A sed that renames Studio
		-- fields can pass every NEGATIVE check; it cannot produce these.
		for _, field in { "instrument", "deviceModel", "capturedAt", "attestedBy" } do
			local row = studioShapedRow()
			row.provenance[field] = nil
			expect(#perf_runner.provenanceProblems(row)).toBe(1)
		end
		local claimsStudio = studioShapedRow()
		claimsStudio.provenance.isStudio = true
		expect(#perf_runner.provenanceProblems(claimsStudio)).toBe(1)
		local absent = studioShapedRow()
		absent.provenance.isStudio = nil
		expect(#perf_runner.provenanceProblems(absent)).toBe(1)
		local wrongClient = studioShapedRow()
		wrongClient.provenance.clientKind = "studio"
		expect(#perf_runner.provenanceProblems(wrongClient)).toBe(1)
	end)

	it("refuses an unmeasured or nonsense frame-work number", function()
		local row = studioShapedRow()
		row.metrics.M1_frameWorkMs = { measured = false, reason = "not taken" }
		expect(#perf_runner.provenanceProblems(row)).toBe(1)
		local negative = studioShapedRow()
		negative.metrics.M1_frameWorkMs = { measured = true, p95_ms = -1 }
		expect(#perf_runner.provenanceProblems(negative)).toBe(1)
	end)

	it("refuses the simulator scaling mode, the fingerprint that was left unread", function()
		local row = studioShapedRow()
		row.device.live.scalingMode = "Enum.DeviceSimulatorScalingMode.ActualResolution"
		expect(#perf_runner.provenanceProblems(row)).toBe(1)
	end)

	it("refuses an attestation that disagrees with the row it sits on", function()
		-- the likeliest HONEST mistake: copy the Studio capture as a template,
		-- write a real attestation and real numbers, forget the device block
		local row = studioShapedRow()
		row.device.name = "Samsung Galaxy S22 Ultra"
		row.provenance.deviceModel = "Pixel 4a"
		local problems = perf_runner.provenanceProblems(row)
		expect(#problems).toBe(1)
		expect(string.find(problems[1], "disagrees", 1, true) ~= nil).toBe(true)
		-- and agrees when they agree
		row.provenance.deviceModel = "Samsung Galaxy S22 Ultra"
		expect(#perf_runner.provenanceProblems(row)).toBe(0)
	end)

	it("catches the whole consistent relabel at once", function()
		-- what `sed s/studio-emulated/phone-physical/g` over the real capture
		-- produces: agreeing labels, and every Studio fingerprint still present
		local row = studioShapedRow()
		row.identity.studioVersion = "0.731.0.7310942"
		row.device.live.deviceId = "samsung_galaxy_s22_ultra"
		row.device.live.source = "StudioDeviceSimulatorService getters"
		expect(#perf_runner.provenanceProblems(row)).toBe(3)
	end)
end)
