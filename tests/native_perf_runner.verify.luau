--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local expect = Verify.expect

	local perf_runner = require("../bench/perf_runner")
	local perf_profiles = require("../bench/perf_profiles")
	local Compose = require("../src/vendor/compose/core")
	local Memory = require("../tools/facet/checks/perf_memory")
	local Engine = require("./lib/native_engine")
	local Evidence = require("../tools/facet/lib/perf_evidence")

	verifyHarness:suite("exact performance resource gates", function()
		verifyHarness:case("rejects each teardown leak and malformed count and reports churn growth", {
			id = "native_perf_runner::exact performance resource gates::rejects each teardown leak and malformed count and reports churn growth",
			run = function()
				local function report(start: unknown, sample: unknown, final: unknown, churn: boolean): unknown
					return {
						runs = {
							{
								scene = "test",
								device = "floorAndroid",
								evidenceClass = "lute",
								samples = 1,
								resources = { start = start, iterations = { sample }, teardown = final, churn = churn },
							},
						},
					}
				end
				local zero = { instances = 0, connections = 0, registrations = 0 }
				expect(Memory.check(report(zero, zero, zero, true))):toEqual({})
				expect(Memory.growth(report(zero, zero, zero, true))):toEqual({})
				for _, name in { "instances", "connections", "registrations" } do
					local leak: { [string]: number } = table.clone(zero)
					leak[name] = 1
					expect(Memory.check(report(zero, leak, zero, true))):toEqual({})
					expect(Memory.growth(report(zero, leak, zero, true))):toEqual({
						`test@floorAndroid: iteration 1 grows {name} from 0 to 1`,
					})
					expect(Memory.growth(report(zero, leak, zero, false))):toEqual({})
					expect(Memory.check(report(zero, zero, leak, false))):toEqual({
						`test@floorAndroid: teardown retains 1 {name}; expected zero`,
					})
					leak[name] = 0.5
					expect(#Memory.check(report(zero, leak, zero, true))):toBe(1)
				end
				expect(#Memory.check({ runs = {} }) > 0):toBe(true)
				expect(#Memory.check({ runs = { { evidenceClass = "lute" } } }) > 0):toBe(true)
			end,
		})
		verifyHarness:case("reports churn growth below the warmed resource count as a trend", {
			id = "native_perf_runner::exact performance resource gates::reports churn growth below the warmed resource count as a trend",
			run = function()
				local function counts(value: number)
					return { instances = value, connections = value, registrations = value }
				end
				local report = {
					runs = {
						{
							scene = "churn",
							device = "floorAndroid",
							evidenceClass = "lute",
							samples = 3,
							resources = {
								start = counts(10),
								iterations = { counts(8), counts(7), counts(8) },
								teardown = counts(0),
								churn = true,
							},
						},
					},
				}
				expect(Memory.check(report)):toEqual({})
				expect(Memory.growth(report)):toEqual({
					"churn@floorAndroid: iteration 3 grows instances from 7 to 8",
					"churn@floorAndroid: iteration 3 grows connections from 7 to 8",
					"churn@floorAndroid: iteration 3 grows registrations from 7 to 8",
				})
			end,
		})
		verifyHarness:case(
			"radial exits release registrations after every close and release all resources on teardown",
			{
				id = "native_perf_runner::exact performance resource gates::radial exits release registrations after every close and release all resources on teardown",
				run = function()
					local scenes = (require("../bench/perf_scenes") :: unknown) :: { { name: string } }
					local found = false
					for _, scene in scenes do
						if scene.name == "radial-menu-open-close" then
							found = true
							local row = perf_runner.runScene(scene, perf_profiles.get(perf_profiles.REFERENCE), {
								warmup = 2,
								samples = 6,
								memory = true,
							})
							expect(Memory.check({ runs = { row } })):toEqual({})
							expect(Memory.growth({ runs = { row } })):toEqual({})
						end
					end
					expect(found):toBe(true)
				end,
			}
		)
	end)

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
				local m = Compose.formula(function(use: Use)
					return use(s) * 2
				end)
				core.owner.watch(function(use: Use)
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

	verifyHarness:suite("perf runner — record schema (§14.3)", function()
		verifyHarness:case("produces a schema-complete record for a tiny scene", {
			id = "native_perf_runner::perf runner — record schema (§14.3)::produces a schema-complete record for a tiny scene",
			run = function()
				local profile = perf_profiles.get(perf_profiles.REFERENCE)
				local rec = perf_runner.runScene(tinyScene(), profile, { warmup = 2, samples = 6 })

				expect(rec.scene):toBe("tiny")
				expect(rec.requirement):toBe("UI-PERF-001")
				expect((type(rec.dataset))):toBe("string")

				expect(rec.device):toBe(profile.name)
				expect((type(rec.deviceTitle))):toBe("string")
				expect(rec.viewport.w):toBe(profile.viewport.w)
				expect((type(rec.quality))):toBe("string")
				expect((type(rec.host))):toBe("string")

				expect((type(rec.engine))):toBe("string")
				expect(rec.warmup):toBe(2)
				expect(rec.samples):toBe(6)
				expect(rec.samplingMs):toBeGreaterThanOrEqual(0)
				expect((type(rec.timestamp))):toBe("string")

				expect(rec.phases.total.p50_ms):toBeGreaterThanOrEqual(0)
				expect(rec.phases.total.p95_ms):toBeGreaterThanOrEqual(0)
				expect(rec.phases.total.p99_ms):toBeGreaterThanOrEqual(0)
				expect(rec.phases.total.samples):toBe(6)
				expect(rec.phases.mutate.p95_ms):toBeGreaterThanOrEqual(0)

				expect((type(rec.allocRateKbPerSec))):toBe("number")
				expect((type(rec.heapSlopeKbPerIter))):toBe("number")

				expect(rec.liveRegistry.registrations):toBeGreaterThanOrEqual(1)
				expect(rec.liveConnections):toBe(rec.liveRegistry.registrations)

				expect(rec.async.dropped):toBe(0)
				expect(rec.async.stale):toBe(0)
				expect((type(rec.async.completed))):toBe("number")

				expect(rec.deviceRun):toBe(false)
				expect(rec.authoritative):toBe(false)
				expect(rec.deviceMeasurement.measured):toBe(false)
				expect((type(rec.note))):toBe("string")
			end,
		})
	end)

	verifyHarness:suite("perf runner — budget enforcement (§16.1)", function()
		verifyHarness:case("audit-only budgets enforce measured physical devices and retain missing capture failures", {
			id = "native_perf_runner::budgets::audit-only physical devices",
			run = function()
				local physical = {
					scene = "hud",
					device = "phone",
					evidenceClass = "phone-physical",
					metrics = {
						frameWorkMs = { measured = true, p95_ms = 2 },
						updateMs = { instrumented = true },
					},
				}
				local headless = {
					scene = "hud",
					device = "floorAndroid",
					evidenceClass = "lute",
					metrics = { updateMs = { instrumented = true } },
					phases = { total = { p95_ms = 100 } },
				}
				local report: { runs: { unknown } } = {
					runs = {
						headless,
						physical,
					},
				}
				local budget = {
					referenceProfile = "floorAndroid",
					scenes = { hud = { total_p95_ms = 1 } },
					deviceBudgets = { ["phone-physical"] = { measured = true, budgetMs = 1 } },
				}
				local failed = perf_runner.checkBudgets(report, budget, false)
				expect(failed.ok):toBe(false)
				expect(#failed.violations):toBe(1)
				expect(failed.violations[1].kind):toBe("device")
				headless.metrics.updateMs.instrumented = false
				headless.phases.total.p95_ms = 0.5
				local historical = perf_runner.checkBudgets(report, budget)
				expect(historical.ok):toBe(false)
				expect(historical.violations[1].kind):toBe("device")
				physical.metrics.frameWorkMs.p95_ms = 0.5
				expect(perf_runner.checkBudgets(report, budget, false).ok):toBe(true)
				physical.metrics.frameWorkMs.measured = false
				local unmeasured = perf_runner.checkBudgets(report, budget, false)
				expect(unmeasured.ok):toBe(false)
				expect(unmeasured.violations[1].kind):toBe("unmeasured-device-row")
				physical.metrics.frameWorkMs.measured = true
				local absent = perf_runner.checkBudgets({ runs = {} }, budget, false)
				expect(absent.ok):toBe(false)
				expect(absent.violations[1].kind):toBe("class-mismatch")
				budget.deviceBudgets["phone-physical"].measured = false
				local pending = perf_runner.checkBudgets(report, budget, false)
				expect(pending.ok):toBe(true)
				expect(#pending.skipped):toBe(1)
				expect(pending.skipped[1].class):toBe("phone-physical")
			end,
		})
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

		verifyHarness:case("flags an over-budget reference-device scene", {
			id = "native_perf_runner::perf runner — budget enforcement (§16.1)::flags an over-budget reference-device scene",
			run = function()
				local res = perf_runner.checkBudgets(report(2.0), budgets)
				expect(res.ok):toBe(false)
				expect(#res.violations):toBe(1)
				local v = res.violations[1]
				expect(v.scene):toBe("hud-binding-storm")
				expect(v.requirement):toBe("UI-PERF-001")
				expect(v.device):toBe("floorAndroid")
				expect(v.observedMs):toBeCloseTo(2.0, 1e-6)
				expect(v.budgetMs):toBeCloseTo(1.0, 1e-6)
				expect((type(v.hint))):toBe("string")
			end,
		})

		verifyHarness:case("passes an in-budget scene (and ignores non-reference devices)", {
			id = "native_perf_runner::perf runner — budget enforcement (§16.1)::passes an in-budget scene (and ignores non-reference devices)",
			run = function()
				local res = perf_runner.checkBudgets(report(0.4), budgets)
				expect(res.ok):toBe(true)
				expect(#res.violations):toBe(0)
			end,
		})
	end)

	verifyHarness:suite("perf runner — shape determinism (§15.2)", function()
		verifyHarness:case("audit-only runs retain every profile, sample and work record in one pass", {
			id = "native_perf_runner::shape::audit-only matrix",
			run = function()
				local setups, steps, settles, teardowns = 0, 0, 0, 0
				local template = tinyScene("dense-hud")
				local scene = {
					name = template.name,
					requirement = template.requirement,
					dataset = template.dataset,
					setup = function(profile)
						setups += 1
						local state = template.setup(profile)
						return {
							core = state.core,
							s = state.s,
							n = state.n,
							engine = Engine.new(),
						}
					end,
					run = function(state)
						steps += 1
						return template.run(state)
					end,
					afterRun = function()
						settles += 1
					end,
					extras = function(state)
						return { activationCount = state.n, activationText = `Boost x{state.n}` }
					end,
					teardown = function(state)
						teardowns += 1
						template.teardown(state)
					end,
				}
				local profiles = {}
				for _, name in perf_profiles.list() do
					table.insert(profiles, perf_profiles.get(name))
				end
				for _, timing in { false, true } do
					setups, steps, settles, teardowns = 0, 0, 0, 0
					local report = perf_runner.run(
						{ scene },
						profiles,
						{ warmup = 2, samples = 3, memory = true, timing = timing }
					)
					local passes = if timing then 2 else 1
					expect({ setups, steps, settles, teardowns }):toEqual({
						5 * passes,
						25 * passes,
						25 * passes,
						5 * passes,
					})
					expect(#report.runs):toBe(5)
					expect(Memory.check(report)):toEqual({})
					local accepted, reason =
						pcall(perf_runner.checkBudgets, report, { referenceProfile = "floorAndroid", scenes = {} })
					expect(accepted):toBe(timing)
					if not timing then
						expect(string.find(tostring(reason), "require uninstrumented scene rows", 1, true) ~= nil):toBe(
							true
						)
					end
					for index, row in report.runs do
						expect(row.device):toBe(profiles[index].name)
						expect(row.warmup):toBe(2)
						expect(row.samples):toBe(3)
						expect(row.phases.total.samples):toBe(3)
						expect(row.metrics.updateMs.instrumented):toBe(not timing)
						expect(#row.resources.iterations):toBe(3)
						expect(Evidence.PRODUCTION["dense-hud"](row.extras)):toBe(nil)
						row.extras.activationCount = 0
						expect(Evidence.PRODUCTION["dense-hud"](row.extras) ~= nil):toBe(true)
					end
				end
			end,
		})
		verifyHarness:case("audit-only execution rejects leaked native resources", {
			id = "native_perf_runner::shape::audit-only leak",
			run = function(context)
				local scene = tinyScene()
				local setup = scene.setup
				local engine = Engine.new()
				local leaked = engine.new("Folder")
				context:defer(function()
					leaked:Destroy()
				end)
				scene.setup = function(profile)
					local state = setup(profile)
					return { core = state.core, s = state.s, n = state.n, engine = engine }
				end
				local report = perf_runner.run(
					{ scene },
					{ perf_profiles.get("phone") },
					{ warmup = 1, samples = 2, memory = true, timing = false }
				)
				expect(Memory.check(report)):toEqual({ "tiny@phone: teardown retains 1 instances; expected zero" })
				local accepted = pcall(perf_runner.run, { scene }, {}, { timing = false })
				expect(accepted):toBe(false)
			end,
		})
		verifyHarness:case("audit-only workload records retain metric provenance checks", {
			id = "native_perf_runner::shape::audit-only provenance",
			run = function()
				local scenes = require("../bench/perf_scenes")
				local function audit(scene: unknown)
					return perf_runner.run(
						{ scene },
						{ perf_profiles.get("floorAndroid") },
						{ warmup = 1, samples = 2, memory = true, timing = false }
					)
				end
				local found = false
				for _, scene in scenes do
					if scene.name ~= "dense-hud" then
						continue
					end
					found = true
					local report = audit(scene)
					expect(Memory.check(report)):toEqual({})
					expect(Evidence.metrics(report).errors):toEqual({})
					report.runs[1].authoritative = true
					expect(#Evidence.metrics(report).errors > 0):toBe(true)
				end
				expect(found):toBe(true)
			end,
		})
		verifyHarness:case("records the same field set and phase set across two runs", {
			id = "native_perf_runner::perf runner — shape determinism (§15.2)::records the same field set and phase set across two runs",
			run = function()
				local profile = perf_profiles.get(perf_profiles.REFERENCE)
				local r1 = perf_runner.runScene(tinyScene(), profile, { warmup = 1, samples = 4 })
				local r2 = perf_runner.runScene(tinyScene(), profile, { warmup = 1, samples = 4 })
				expect((keys(r1))):toEqual(keys(r2))
				expect((keys(r1.phases))):toEqual(keys(r2.phases))
				expect((keys(r1.async))):toEqual(keys(r2.async))
				expect((keys(r1.liveRegistry))):toEqual(keys(r2.liveRegistry))
			end,
		})

		verifyHarness:case("run() covers the full scene×profile matrix with a stable key set", {
			id = "native_perf_runner::perf runner — shape determinism (§15.2)::run() covers the full scene×profile matrix with a stable key set",
			run = function()
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

				expect(rep1.schema):toBe("facet-perf/2")
				expect(#rep1.runs):toBe(4)
				expect((matrixKeys(rep1))):toEqual({ "a@desktop", "a@floorAndroid", "b@desktop", "b@floorAndroid" })
				expect((matrixKeys(rep1))):toEqual(matrixKeys(rep2))
			end,
		})
	end)

	verifyHarness:suite("perf runner settle boundary", function()
		verifyHarness:case("settles after each warmup and sample before the next event", {
			id = "native_perf_runner::perf runner settle boundary::settles after each warmup and sample before the next event",
			run = function()
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
				expect(order):toEqual({ "event", "settle", "event", "settle", "event", "settle" })
			end,
		})
	end)
end
