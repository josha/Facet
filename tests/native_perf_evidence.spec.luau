--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
	local expect = Verify.expect

	local perf_runner = require("../bench/perf_runner")
	local perf_profiles = require("../bench/perf_profiles")
	local Compose = require("../src/vendor/compose/core")

	local function tinyScene(name: string?)
		return {
			name = name or "tiny",
			requirement = "UI-PERF-001",
			dataset = "1 signal; 3 writes per iteration",
			setup = function(_profile: any)
				local core = Compose.createRootOwner(function() end)
				local s = Compose.cell(0)
				return { core = core, s = s, n = 0 }
			end,
			teardown = function(state)
				state.core.dispose()
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

	verifyHarness:suite("evidence classes (UI-PERF-002)", function()
		verifyHarness:case("every record carries exactly one evidence class, and Lune may only emit the headless one", {
			id = "native_perf_evidence::evidence classes (UI-PERF-002)::every record carries exactly one evidence class, and Lune may only emit the headless one",
			run = function()
				local profile = perf_profiles.get(perf_profiles.REFERENCE)
				local rec = perf_runner.runScene(tinyScene(), profile, { warmup = 1, samples = 3 })
				expect(rec.evidenceClass):toBe("lune")
				expect(rec.evidenceLevel):toBe("E1")

				expect(perf_runner.CLASS):toBe("lune")
				expect(perf_runner.DEVICE_CLASSES.lune):toBe(nil)
				expect(perf_runner.DEVICE_CLASSES["phone-physical"]):toBe(true)
			end,
		})

		verifyHarness:case("declares every class in the inventory, including the ones with zero rows", {
			id = "native_perf_evidence::evidence classes (UI-PERF-002)::declares every class in the inventory, including the ones with zero rows",
			run = function()
				local rep = perf_runner.run(
					{ tinyScene("a") },
					{ perf_profiles.get("desktop") },
					{ warmup = 1, samples = 2 }
				)
				local byId: { [string]: any } = {}
				for _, c in rep.evidenceClasses do
					byId[c.id] = c
				end
				expect(byId.lune.rows):toBe(1)

				expect(byId["phone-physical"].rows):toBe(0)
				expect(byId["console-physical"].rows):toBe(0)
				expect(byId["desktop-retail"].rows):toBe(0)
				expect((type(byId["phone-physical"].cannotProve))):toBe("string")
			end,
		})

		verifyHarness:case("a metric the instrument cannot see is a blind marker with a reason, not a zero", {
			id = "native_perf_evidence::evidence classes (UI-PERF-002)::a metric the instrument cannot see is a blind marker with a reason, not a zero",
			run = function()
				local rec = perf_runner.runScene(
					tinyScene(),
					perf_profiles.get(perf_profiles.REFERENCE),
					{ warmup = 1, samples = 3 }
				)

				expect(rec.metrics.frameWorkMs.measured):toBe(false)
				expect(#rec.metrics.frameWorkMs.reason > 0):toBe(true)

				expect(rec.metrics.inputToVisibleMs.measured):toBe(false)

				expect(rec.metrics.themeSwap.measured):toBe(false)

				expect(rec.metrics.updateMs.measured):toBe(true)
				expect(rec.metrics.memoryKb.measured):toBe(true)
			end,
		})

		verifyHarness:case("lifts a scene-declared inputToVisible phase into the M6 slot", {
			id = "native_perf_evidence::evidence classes (UI-PERF-002)::lifts a scene-declared inputToVisible phase into the M6 slot",
			run = function()
				local scene = tinyScene("driven")
				scene.run = function(state: any): { [string]: number }?
					state.n += 1
					local t0 = os.clock()
					state.s:set(state.n)
					return { inputToVisible = os.clock() - t0 }
				end
				local rec = perf_runner.runScene(scene, perf_profiles.get("desktop"), { warmup = 1, samples = 3 })
				expect(rec.metrics.inputToVisibleMs.measured):toBe(true)
				expect(rec.metrics.inputToVisibleMs.p95_ms):toBeGreaterThanOrEqual(0)

				expect(string.find(rec.metrics.inputToVisibleMs.note, "no frame", 1, true) ~= nil):toBe(true)
			end,
		})
	end)

	verifyHarness:suite("device budgets are unreachable from the wrong class (UI-PERF-002)", function()
		local function headlessReport(): {
			schema: string,
			environment: { evidenceClass: string },
			referenceProfile: string,
			runs: { { [string]: any } },
		}
			return {
				schema = "facet-perf/2",
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

		verifyHarness:case("refuses to enforce a device budget from a non-device class", {
			id = "native_perf_evidence::device budgets are unreachable from the wrong class (UI-PERF-002)::refuses to enforce a device budget from a non-device class",
			run = function()
				local budgets = {
					referenceProfile = "floorAndroid",
					scenes = {},
					deviceBudgets = {
						["phone-physical"] = { budgetMs = 8.33, measured = true, requirement = "UI-PERF-002" },
					},
				}
				local result = perf_runner.checkBudgets(headlessReport(), budgets)
				expect(result.ok):toBe(false)
				expect(#result.violations):toBe(1)
				expect(result.violations[1].kind):toBe("class-mismatch")
				expect(result.violations[1].device):toBe("phone-physical")

				expect(string.find(result.violations[1].hint, "no rows of", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("skips an unmeasured device budget LOUDLY rather than silently passing it", {
			id = "native_perf_evidence::device budgets are unreachable from the wrong class (UI-PERF-002)::skips an unmeasured device budget LOUDLY rather than silently passing it",
			run = function()
				local budgets = {
					referenceProfile = "floorAndroid",
					scenes = {},
					deviceBudgets = {
						["console-physical"] = { budgetMs = 4.17, measured = false },
					},
				}
				local result = perf_runner.checkBudgets(headlessReport(), budgets)
				expect(result.ok):toBe(true)
				expect(#result.skipped):toBe(1)
				expect(result.skipped[1].class):toBe("console-physical")
				expect(string.find(result.skipped[1].reason, "PENDING_PHYSICAL", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("a device-class row with no measured frame work does not satisfy its budget", {
			id = "native_perf_evidence::device budgets are unreachable from the wrong class (UI-PERF-002)::a device-class row with no measured frame work does not satisfy its budget",
			run = function()
				local rep = headlessReport()
				table.insert(rep.runs, {
					scene = "hud-binding-storm",
					device = "pixel-4a",
					evidenceClass = "phone-physical",
					requirement = "UI-PERF-002",
					phases = { total = { p50_ms = 1, p95_ms = 2, p99_ms = 3 } },
				})
				local result = perf_runner.checkBudgets(rep, {
					referenceProfile = "floorAndroid",
					scenes = {},
					deviceBudgets = {
						["phone-physical"] = { budgetMs = 0.001, measured = true, requirement = "UI-PERF-002" },
					},
				})
				expect(result.ok):toBe(false)
				expect(result.violations[1].kind):toBe("unmeasured-device-row")
				expect(string.find(result.violations[1].hint, "not by an evidence-class", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("a device row whose frame work is blind does not error the budget check", {
			id = "native_perf_evidence::device budgets are unreachable from the wrong class (UI-PERF-002)::a device row whose frame work is blind does not error the budget check",
			run = function()
				local rep = headlessReport()
				table.insert(rep.runs, {
					scene = "dense-hud",
					device = "pixel-4a",
					evidenceClass = "phone-physical",
					requirement = "UI-PERF-002",
					phases = { total = { p50_ms = 1, p95_ms = 2, p99_ms = 3 } },
					metrics = {
						frameWorkMs = { measured = false, reason = "the capture tool could not read frame time" },
					},
				})
				local ok, result = pcall(perf_runner.checkBudgets, rep, {
					referenceProfile = "floorAndroid",
					scenes = {},
					deviceBudgets = {
						["phone-physical"] = { budgetMs = 8.33, measured = true, requirement = "UI-PERF-002" },
					},
				})
				expect(ok):toBe(true)
				expect(result.ok):toBe(false)
				expect(result.violations[1].kind):toBe("unmeasured-device-row")
			end,
		})

		verifyHarness:case("a NaN or negative frame time is not a measurement", {
			id = "native_perf_evidence::device budgets are unreachable from the wrong class (UI-PERF-002)::a NaN or negative frame time is not a measurement",
			run = function()
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
					expect(result.ok):toBe(false)
					expect(result.violations[1].kind):toBe("unmeasured-device-row")
				end
			end,
		})

		verifyHarness:case("refuses without throwing on a hand-authored report that has no environment block", {
			id = "native_perf_evidence::device budgets are unreachable from the wrong class (UI-PERF-002)::refuses without throwing on a hand-authored report that has no environment block",
			run = function()
				local ok, result = pcall(perf_runner.checkBudgets, {
					schema = "facet-perf/2",
					runs = {
						{
							scene = "x",
							device = "floorAndroid",
							evidenceClass = "lune",
							phases = { total = { p95_ms = 1 } },
						},
					},
				}, {
					referenceProfile = "floorAndroid",
					scenes = {},
					deviceBudgets = { ["phone-physical"] = { budgetMs = 8.33, measured = true } },
				})
				expect(ok):toBe(true)
				expect(result.ok):toBe(false)
				expect(result.violations[1].kind):toBe("class-mismatch")
				expect(string.find(result.violations[1].hint, "unstated", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("enforces a device budget only against rows of its own class", {
			id = "native_perf_evidence::device budgets are unreachable from the wrong class (UI-PERF-002)::enforces a device budget only against rows of its own class",
			run = function()
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
				expect(result.ok):toBe(false)
				expect(result.violations[1].kind):toBe("device")
				expect(result.violations[1].observedMs):toBe(12.0)

				expect(#result.violations):toBe(1)
			end,
		})
	end)

	verifyHarness:suite("the frame ceiling is one-directional (UI-PERF-002)", function()
		verifyHarness:case("derives the ceiling from the frame target and the declared UI share", {
			id = "native_perf_evidence::the frame ceiling is one-directional (UI-PERF-002)::derives the ceiling from the frame target and the declared UI share",
			run = function()
				local ceiling = perf_runner.ceilingMsFor(30, 0.25)
				expect(math.abs(ceiling - 8.3333) < 0.001):toBe(true)
				expect(math.abs(perf_runner.ceilingMsFor(60, 0.25) - 4.1666) < 0.001):toBe(true)
			end,
		})

		verifyHarness:case("flags a scene above the ceiling separately from a trend regression", {
			id = "native_perf_evidence::the frame ceiling is one-directional (UI-PERF-002)::flags a scene above the ceiling separately from a trend regression",
			run = function()
				local rep = {
					schema = "facet-perf/2",
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
				expect(result.ok):toBe(false)
				expect(result.violations[1].kind):toBe("frame-ceiling")
				expect(string.find(result.violations[1].hint, "cannot hold the frame target anywhere", 1, true) ~= nil):toBe(
					true
				)
			end,
		})
	end)

	verifyHarness:suite("console / ten-foot profile (UI-PARADIGM-003, XP-A1)", function()
		verifyHarness:case("is in the headless matrix", {
			id = "native_perf_evidence::console / ten-foot profile (UI-PARADIGM-003, XP-A1)::is in the headless matrix",
			run = function()
				local names = perf_profiles.list()
				local found = false
				for _, n in names do
					if n == "consoleTenFoot" then
						found = true
					end
				end
				expect(found):toBe(true)
			end,
		})

		verifyHarness:case("declares ten-foot display and gamepad facts", {
			id = "native_perf_evidence::console / ten-foot profile (UI-PARADIGM-003, XP-A1)::declares ten-foot display and gamepad facts",
			run = function()
				local core = Compose.createRootOwner(function() end)
				local profile = perf_profiles.get("consoleTenFoot")
				expect(profile.displaySize):toBe("Large")
				expect(profile.preferredInput):toBe("Gamepad")
				expect(profile.overscanInsets.left):toBeGreaterThan(0)
				expect(profile.capabilities.gamepad):toBe(true)
				core.dispose()
			end,
		})

		verifyHarness:case("declares a frame target for every profile, so a ceiling can be derived", {
			id = "native_perf_evidence::console / ten-foot profile (UI-PARADIGM-003, XP-A1)::declares a frame target for every profile, so a ceiling can be derived",
			run = function()
				for _, name in perf_profiles.list() do
					local p = perf_profiles.get(name)
					expect((type(p.frameTargetHz))):toBe("number")
					expect(p.frameTargetHz > 0):toBe(true)
				end

				expect(perf_profiles.get("floorAndroid").frameTargetHz):toBe(30)
				expect(perf_profiles.get("consoleTenFoot").frameTargetHz):toBe(60)
			end,
		})
	end)

	verifyHarness:suite("physical-row provenance", function()
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
					attestedBy = "maintainer",
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

		verifyHarness:case("accepts a row that carries everything its class implies", {
			id = "native_perf_evidence::physical-row provenance::accepts a row that carries everything its class implies",
			run = function()
				expect(#perf_runner.provenanceProblems(studioShapedRow())):toBe(0)
			end,
		})

		verifyHarness:case("says nothing about a row that is not of a device class", {
			id = "native_perf_evidence::physical-row provenance::says nothing about a row that is not of a device class",
			run = function()
				local row = studioShapedRow()
				row.evidenceClass = "studio-emulated"
				row.identity.studioVersion = "0.731.0.7310942"
				expect(#perf_runner.provenanceProblems(row)):toBe(0)
			end,
		})

		verifyHarness:case("refuses a physical row that carries a Studio version", {
			id = "native_perf_evidence::physical-row provenance::refuses a physical row that carries a Studio version",
			run = function()
				local row = studioShapedRow()
				row.identity.studioVersion = "0.731.0.7310942"
				local problems = perf_runner.provenanceProblems(row)
				expect(#problems):toBe(1)
				expect(string.find(problems[1], "studioVersion", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("refuses a physical row that names a device-simulator preset", {
			id = "native_perf_evidence::physical-row provenance::refuses a physical row that names a device-simulator preset",
			run = function()
				local row = studioShapedRow()
				row.device.live.deviceId = "samsung_galaxy_s22_ultra"
				expect(#perf_runner.provenanceProblems(row)):toBe(1)
			end,
		})

		verifyHarness:case("refuses a physical row whose live facts came from the Studio simulator", {
			id = "native_perf_evidence::physical-row provenance::refuses a physical row whose live facts came from the Studio simulator",
			run = function()
				local row = studioShapedRow()
				row.device.live.source = "StudioDeviceSimulatorService getters"
				expect(#perf_runner.provenanceProblems(row)):toBe(1)
			end,
		})

		verifyHarness:case("refuses the Studio evidence level under a physical class", {
			id = "native_perf_evidence::physical-row provenance::refuses the Studio evidence level under a physical class",
			run = function()
				local row = studioShapedRow()
				row.evidenceLevel = "E3"
				local problems = perf_runner.provenanceProblems(row)
				expect(#problems):toBe(1)
				expect(string.find(problems[1], "E4", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("refuses a hand-written row with one number in it", {
			id = "native_perf_evidence::physical-row provenance::refuses a hand-written row with one number in it",
			run = function()
				local problems = perf_runner.provenanceProblems({
					evidenceClass = "phone-physical",
					evidenceLevel = "E4",
					metrics = { frameWorkMs = { measured = true, p95_ms = 1.2 } },
				})

				expect(#problems >= 5):toBe(true)
			end,
		})

		verifyHarness:case("refuses a row that carries no attestation at all", {
			id = "native_perf_evidence::physical-row provenance::refuses a row that carries no attestation at all",
			run = function()
				local row = studioShapedRow()
				row.provenance = nil
				local problems = perf_runner.provenanceProblems(row)
				expect(#problems):toBe(1)
				expect(string.find(problems[1], "provenance", 1, true) ~= nil):toBe(true)
			end,
		})

		verifyHarness:case("refuses an attestation with a field renamed rather than written", {
			id = "native_perf_evidence::physical-row provenance::refuses an attestation with a field renamed rather than written",
			run = function()
				for _, field in { "instrument", "deviceModel", "capturedAt", "attestedBy" } do
					local row = studioShapedRow()
					row.provenance[field] = nil
					expect(#perf_runner.provenanceProblems(row)):toBe(1)
				end
				local claimsStudio = studioShapedRow()
				claimsStudio.provenance.isStudio = true
				expect(#perf_runner.provenanceProblems(claimsStudio)):toBe(1)
				local absent = studioShapedRow()
				absent.provenance.isStudio = nil
				expect(#perf_runner.provenanceProblems(absent)):toBe(1)
				local wrongClient = studioShapedRow()
				wrongClient.provenance.clientKind = "studio"
				expect(#perf_runner.provenanceProblems(wrongClient)):toBe(1)
			end,
		})

		verifyHarness:case("refuses an unmeasured or nonsense frame-work number", {
			id = "native_perf_evidence::physical-row provenance::refuses an unmeasured or nonsense frame-work number",
			run = function()
				local row = studioShapedRow()
				row.metrics.M1_frameWorkMs = { measured = false, reason = "not taken" }
				expect(#perf_runner.provenanceProblems(row)):toBe(1)
				local negative = studioShapedRow()
				negative.metrics.M1_frameWorkMs = { measured = true, p95_ms = -1 }
				expect(#perf_runner.provenanceProblems(negative)):toBe(1)
			end,
		})

		verifyHarness:case("refuses the simulator scaling mode, the fingerprint that was left unread", {
			id = "native_perf_evidence::physical-row provenance::refuses the simulator scaling mode, the fingerprint that was left unread",
			run = function()
				local row = studioShapedRow()
				row.device.live.scalingMode = "Enum.DeviceSimulatorScalingMode.ActualResolution"
				expect(#perf_runner.provenanceProblems(row)):toBe(1)
			end,
		})

		verifyHarness:case("refuses an attestation that disagrees with the row it sits on", {
			id = "native_perf_evidence::physical-row provenance::refuses an attestation that disagrees with the row it sits on",
			run = function()
				local row = studioShapedRow()
				row.device.name = "Samsung Galaxy S22 Ultra"
				row.provenance.deviceModel = "Pixel 4a"
				local problems = perf_runner.provenanceProblems(row)
				expect(#problems):toBe(1)
				expect(string.find(problems[1], "disagrees", 1, true) ~= nil):toBe(true)

				row.provenance.deviceModel = "Samsung Galaxy S22 Ultra"
				expect(#perf_runner.provenanceProblems(row)):toBe(0)
			end,
		})

		verifyHarness:case("catches the whole consistent relabel at once", {
			id = "native_perf_evidence::physical-row provenance::catches the whole consistent relabel at once",
			run = function()
				local row = studioShapedRow()
				row.identity.studioVersion = "0.731.0.7310942"
				row.device.live.deviceId = "samsung_galaxy_s22_ultra"
				row.device.live.source = "StudioDeviceSimulatorService getters"
				expect(#perf_runner.provenanceProblems(row)):toBe(3)
			end,
		})
	end)
end
