--!strict
-- The performance lab's SCENARIO REGISTRY (roadmap Step 9, acceptance PL-2/PL-16).
--
-- Same contract as `examples/gallery/scenarios/init.luau` — `{ order, modules,
-- runner }` — because the lab REUSES the gallery's scenario runner rather than
-- growing a second one. The `runner` child is mapped into this folder by
-- `examples/performance.project.json` (Rojo `$path` plus one extra child), so
-- there is exactly one runner implementation in the repository and the lab's
-- Studio surface is the same surface every other stage was verified through.
--
-- ONE registered scenario, `perf_lab`, whose nine workloads are selected inside
-- the session. See perf_lab.luau for why that split exists.
--
-- The place doctor (`tools/check_perf_place.py`) asserts every name below exists
-- as a ModuleScript inside the built `.rbxl`, so a build that silently drops a
-- module fails at the gate rather than at the phone.

local ORDER = { "perf_lab" }

local MODULE_NAMES = { "perf_lab", "dataset", "rows", "capture", "overlay", "levers" }

local scenarios = {}
for _, name in ORDER do
	scenarios[name] = script:WaitForChild(name)
end

-- The engine-free modules perf_lab is handed through `ctx.lab`. They are required
-- HERE (one place, one time) rather than by perf_lab itself, because perf_lab
-- must stay `script`-free to keep running under Lune in the headless scene and
-- the headless test.
local lab = {
	dataset = require(script:WaitForChild("dataset")) :: any,
	rows = require(script:WaitForChild("rows")) :: any,
	capture = require(script:WaitForChild("capture")) :: any,
	overlay = require(script:WaitForChild("overlay")) :: any,
	-- the two named levers of device-capture-2026-08-15 §7: `arrange-shapes` and
	-- `edit-locality`. Its own file because perf_lab is close to the 200,000-char
	-- live-sync cap; see levers.luau's header.
	levers = require(script:WaitForChild("levers")) :: any,
}

return {
	order = ORDER,
	modules = scenarios,
	moduleNames = MODULE_NAMES,
	lab = lab,
	runner = script:WaitForChild("runner"),
	-- THE SHARED RUNNER READS THIS UNCONDITIONALLY, so the lab has to supply it
	-- even though no lab workload uses `UI.Foreign` (ADR-0034). `runner.luau` is
	-- GRAFTED into this folder by `examples/performance.project.json` — one runner
	-- for the gallery and the lab, deliberately, so the test rig cannot end up more
	-- capable than the surface a player opens — and it requires
	-- `registry.foreignInstances` at the top of `start`, before it even looks at
	-- which scenario was asked for.
	--
	-- IT WAS MISSING FROM 2026-08-15 (`cad3617`, the UI.Foreign showcase, which
	-- added that require) UNTIL 2026-08-17, and in that window pressing Play in the
	-- Performance Lab did nothing at all: `Attempted to call require with invalid
	-- argument(s)` out of `FacetScenarios.runner:217`. Nothing caught it because
	-- the lab is only opened when somebody takes a capture, and the headless suite
	-- requires these modules directly rather than through the built place. The
	-- registry-contract check in `tests/perf_lab.spec.luau` is the guard that would
	-- have.
	foreignInstances = script:WaitForChild("foreign_instances"),
}
