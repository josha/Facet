--!strict
--[[ Backdrop-finding SWEEP capture (task POP fix round 1, CRITICAL finding).

	The round-0 gate (`tests/backdrop_fade.spec.luau`) proved the mechanism and
	covered ONE reference app's four main modals. The review's own probe (task
	POP fix round 1) showed the gate was never actually POINTED at the other
	four reference apps, the showcase scenarios, or RascalRally — and a live
	instance of the exact bug shipped in RascalRally's own production code as
	a direct result. This helper makes "point the gate at a whole app run" a
	one-line wrap instead of something each sweep spec re-invents.

	`sweep.capture(drive)` wraps `transitions.new` for the duration of
	`drive()` so EVERY coordinator the app creates while `drive` runs (the
	main screen's `present()`, every `presentModal()`, every toast layer —
	`src/present/presenter.luau` calls `transitionsLib.new({...})` once per
	surface) is captured, then returns the UNION of every one of those
	coordinators' own `.findings()` — the SAME structural fact
	`coordinator.findings()` reports per-surface, aggregated across a whole
	driven session with ZERO app-specific wiring (no monkey-patching
	`presentModal` per app, no knowledge of how many surfaces an app opens).

	WHY THIS IS SOUND, not a guess: `presenter.luau` holds `transitionsLib` as
	a `require`d table reference — `require` caches by resolved path, so a
	test requiring the SAME file gets the SAME table, and reassigning its
	`new` field here is visible to every module that already required it.
	Restored in a `finally`-shaped `pcall` wrapper so a `drive` that throws
	still leaves the module unpatched for the next spec. ]]

local transitionsLib = require("../../src/render/transitions")

local sweep = {}

export type Finding = { path: string, backdropPath: string, surface: string?, via: string }

-- runs `drive()` with every coordinator it creates captured; returns the
-- UNION of their `.findings()`. Re-entrant-safe (nested `capture` calls are
-- not supported — `drive` should not itself call `sweep.capture`).
function sweep.capture(drive: () -> ()): { Finding }
	local coordinators: { any } = {}
	local original = transitionsLib.new
	transitionsLib.new = function(opts: any): any
		local coord = original(opts)
		table.insert(coordinators, coord)
		return coord
	end
	local ok, err = pcall(drive)
	transitionsLib.new = original
	if not ok then
		error(err, 0)
	end
	local out: { Finding } = {}
	for _, coord in coordinators do
		for _, finding in coord.findings() do
			table.insert(out, finding)
		end
	end
	return out
end

-- a one-line failure message naming every finding, for a single `expect`
function sweep.describe(findings: { Finding }): string
	local lines: { string } = {}
	for _, f in findings do
		table.insert(lines, transitionsLib.backdropIssue(f :: any))
	end
	return table.concat(lines, "\n")
end

return sweep
