--!strict

local t = require("./lib/testkit")
local describe, it, expect = t.describe, t.it, t.expect

local perf_runner = require("../bench/perf_runner")
local perf_profiles = require("../bench/perf_profiles")
local Compose = require("../src/vendor/compose/core")

local function keys(tbl: any): { string }
	local out = {}
	for k in tbl do
		table.insert(out, tostring(k))
	end
	table.sort(out)
	return out
end

local function tinyScene(name: string?)
	return {
		name = name or "tiny",
		requirement = "UI-PERF-001",
		dataset = "1 signal / 1 memo / 1 observer; 5 writes per iteration",
		setup = function(_profile: any)
			local core = Compose.createRootOwner(function() end)
			local s = Compose.cell(0)
			local m = Compose.formula(function(use)
				return use(s) * 2
			end)
			core.owner.watch(function(use)
				use(m)
			end)
			return { core = core, s = s, n = 0 }
		end,
		teardown = function(state)
			state.core.dispose()
		end,
		run = function(state: any): { [string]: number }?
			local t0 = os.clock()
			state.n += 1
			for i = 1, 5 do
				state.s:set(state.n * 5 + i)
			end
			return { mutate = os.clock() - t0 }
		end,
	}
end

describe("perf runner — record schema (§14.3)", function()
	it("produces a schema-complete record for a tiny scene", function()
		local profile = perf_profiles.get(perf_profiles.REFERENCE)
		local rec = perf_runner.runScene(tinyScene(), profile, { warmup = 2, samples = 6 })

		expect(rec.scene).toBe("tiny")
		expect(rec.requirement).toBe("UI-PERF-001")
		expect(type(rec.dataset)).toBe("string")

		expect(rec.device).toBe(profile.name)
		expect(type(rec.deviceTitle)).toBe("string")
		expect(rec.viewport.w).toBe(profile.viewport.w)
		expect(type(rec.quality)).toBe("string")
		expect(type(rec.host)).toBe("string")

		expect(type(rec.engine)).toBe("string")
		expect(rec.warmup).toBe(2)
		expect(rec.samples).toBe(6)
		expect(rec.samplingMs).toBeGreaterThanOrEqual(0)
		expect(type(rec.timestamp)).toBe("string")

		expect(rec.phases.total.p50_ms).toBeGreaterThanOrEqual(0)
		expect(rec.phases.total.p95_ms).toBeGreaterThanOrEqual(0)
		expect(rec.phases.total.p99_ms).toBeGreaterThanOrEqual(0)
		expect(rec.phases.total.samples).toBe(6)
		expect(rec.phases.mutate.p95_ms).toBeGreaterThanOrEqual(0)

		expect(type(rec.allocRateKbPerSec)).toBe("number")
		expect(type(rec.heapSlopeKbPerIter)).toBe("number")

		expect(rec.liveRegistry.registrations).toBeGreaterThanOrEqual(1)
		expect(rec.liveConnections).toBe(rec.liveRegistry.registrations)

		expect(rec.async.dropped).toBe(0)
		expect(rec.async.stale).toBe(0)
		expect(type(rec.async.completed)).toBe("number")

		expect(rec.deviceRun).toBe(false)
		expect(rec.authoritative).toBe(false)
		expect(rec.deviceMeasurement.measured).toBe(false)
		expect(type(rec.note)).toBe("string")
	end)
end)

describe("perf runner — budget enforcement (§16.1)", function()
	local function report(p95: number)
		return {
			schema = "facet-perf/1",
			referenceProfile = "floorAndroid",
			runs = {
				{
					scene = "hud-binding-storm",
					device = "floorAndroid",
					requirement = "UI-PERF-001",
					phases = { total = { p50_ms = p95 / 2, p95_ms = p95, p99_ms = p95 } },
				},

				{
					scene = "hud-binding-storm",
					device = "desktop",
					requirement = "UI-PERF-001",
					phases = { total = { p50_ms = 99, p95_ms = 99, p99_ms = 99 } },
				},
			},
		}
	end
	local budgets = {
		referenceProfile = "floorAndroid",
		scenes = {
			["hud-binding-storm"] = {
				total_p95_ms = 1.0,
				requirement = "UI-PERF-001",
				hint = "profile the HUD memo chain",
			},
		},
	}

	it("flags an over-budget reference-device scene", function()
		local res = perf_runner.checkBudgets(report(2.0), budgets)
		expect(res.ok).toBe(false)
		expect(#res.violations).toBe(1)
		local v = res.violations[1]
		expect(v.scene).toBe("hud-binding-storm")
		expect(v.requirement).toBe("UI-PERF-001")
		expect(v.device).toBe("floorAndroid")
		expect(v.observedMs).toBeCloseTo(2.0, 1e-6)
		expect(v.budgetMs).toBeCloseTo(1.0, 1e-6)
		expect(type(v.hint)).toBe("string")
	end)

	it("passes an in-budget scene (and ignores non-reference devices)", function()
		local res = perf_runner.checkBudgets(report(0.4), budgets)
		expect(res.ok).toBe(true)
		expect(#res.violations).toBe(0)
	end)
end)

describe("perf runner — shape determinism (§15.2)", function()
	it("records the same field set and phase set across two runs", function()
		local profile = perf_profiles.get(perf_profiles.REFERENCE)
		local r1 = perf_runner.runScene(tinyScene(), profile, { warmup = 1, samples = 4 })
		local r2 = perf_runner.runScene(tinyScene(), profile, { warmup = 1, samples = 4 })
		expect(keys(r1)).toEqual(keys(r2))
		expect(keys(r1.phases)).toEqual(keys(r2.phases))
		expect(keys(r1.async)).toEqual(keys(r2.async))
		expect(keys(r1.liveRegistry)).toEqual(keys(r2.liveRegistry))
	end)

	it("run() covers the full scene×profile matrix with a stable key set", function()
		local scenes = { tinyScene("a"), tinyScene("b") }
		local profiles = { perf_profiles.get("floorAndroid"), perf_profiles.get("desktop") }
		local opts = { warmup = 1, samples = 3 }
		local function matrixKeys(rep: any): { string }
			local out = {}
			for _, r in rep.runs do
				table.insert(out, `{r.scene}@{r.device}`)
			end
			table.sort(out)
			return out
		end
		local rep1 = perf_runner.run(scenes, profiles, opts)
		local rep2 = perf_runner.run(scenes, profiles, opts)

		expect(rep1.schema).toBe("facet-perf/2")
		expect(#rep1.runs).toBe(4)
		expect(matrixKeys(rep1)).toEqual({ "a@desktop", "a@floorAndroid", "b@desktop", "b@floorAndroid" })
		expect(matrixKeys(rep1)).toEqual(matrixKeys(rep2))
	end)
end)

describe("perf runner settle boundary", function()
	it("settles after each warmup and sample before the next event", function()
		local order = {}
		local scene = {
			name = "settle",
			requirement = "UI-PERF-001",
			dataset = "boundary",
			setup = function()
				return {}
			end,
			run = function()
				table.insert(order, "event")
			end,
			afterRun = function()
				table.insert(order, "settle")
			end,
		}
		perf_runner.runScene(scene, perf_profiles.get("phone"), { warmup = 1, samples = 2 })
		expect(order).toEqual({ "event", "settle", "event", "settle", "event", "settle" })
	end)
end)
