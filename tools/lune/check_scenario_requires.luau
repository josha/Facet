--!strict
--[[ Headless-vs-instance-tree require guard (SHOWCASE2 task A: the "All controls"
	empty-mount defect, the SECOND divergence of this shape this campaign — G7+G11's
	Rojo mount-depth was the first, docs/adr/ADR-0048).

	Lune resolves a relative `require("../../foo")` by FILE-SYSTEM path. Live Rojo/
	Studio resolves the IDENTICAL string by INSTANCE-TREE depth. The two only agree
	when a file's disk depth under its own Rojo mount matches its instance depth
	under `ReplicatedStorage` — which breaks the moment a module reaches OUT of its
	own mount into a sibling tree with enough `../` to escape it, because
	`examples/gallery/scenarios` (2 levels under ReplicatedStorage) and `src`
	(1 level under ReplicatedStorage) are SIBLINGS in the built place, not nested,
	even though `src` sits 3 directories up from `examples/gallery/scenarios` on
	disk. Three live instances of exactly this shipped before this guard existed —
	all three are `local x = require("../../../src/...")` at MODULE SCOPE,
	unguarded:

	  - examples/gallery/scenarios/adaptive_controls.luau (chrome_slots) — the
	    live defect this task fixes (commit 5805244).
	  - examples/gallery/scenarios/nested_compositing.luau (transform_footprint).
	  - examples/reference/p4_foyer/init.luau (chrome_slots).

	They were first fixed with the idiom `sensory_feedback.luau`'s
	`resolveAdapterModule` established: try the ENGINE route
	(`require((game):GetService("ReplicatedStorage").Facet...)`) first, fall back
	to the FILE route (the same literal string this guard would otherwise flag),
	both pcall-guarded, resolved lazily inside a function — never at module scope.
	That fallback string is deliberately not resolvable in the live tree; it only
	ever runs under Lune, where the engine route fails immediately (no `game`).
	This guard must not flag it, so it only inspects requires that would run
	UNCONDITIONALLY when the module loads: `require(...)` on a line with ZERO
	leading whitespace (module scope). A guarded fallback always sits indented
	inside a `pcall(function() ... end)` body, so this is precise, not a proxy —
	confirmed against the fixed sites plus both already-shipped safe fallbacks
	(sensory_feedback.luau, and this file's own two new ones).

	THE THREE SITES ABOVE NO LONGER REACH ACROSS THE TREES AT ALL (2026-08-29).
	The engine route is an INSTANCE PATH into a framework internal, which is what
	`tools/lune/check_boundary`'s `consumer-requires-facet-internal` rule flags an
	example for — so all three moved onto the public surface they never needed to
	leave: `Facet.layout.transformFootprint` off the library handle the host
	already passes in, and the documented `chromeInsets` field of the theme
	snapshot both badge sites already held. Nothing resolves, so nothing had to be
	resolved. `sensory_feedback.luau`'s reach for a CLIENT ADAPTER module — which
	genuinely has no public equivalent — is the one live user of the idiom, and it
	is what keeps this guard's negative cases honest. The guard itself is
	unchanged and still enforcing: the class it names is a property of the two
	mount trees, not of these three files.

	Scope: every EXAMPLE/SCENARIO/REFERENCE file the `studio_sync` manifest would
	serve into the same place `tools/studio/inject.luau` patches Studio with —
	`ReplicatedStorage.{FacetThemes,FacetExamples,FacetScenarios,FacetReference}`
	plus the Gallery bootstrap script — checked against the FULL tree (including
	`ReplicatedStorage.Facet`, since that is exactly what a gallery/scenario file
	is reaching FOR). `ReplicatedStorage.Facet` (`src/`) is excluded from the
	FILES SCANNED, not from the targets a require may land on: `src/`'s own
	internal requires never cross a mount boundary (same tree throughout, so
	Lune and Studio agree by construction) except one pre-existing, KNOWN,
	deliberately-inert case — `src/core/fusion_adapter.luau`'s vendored-Fusion
	reach — which is not on any live boot path (`src/init.luau` never requires
	it; `vendor/Fusion` is not even mounted into the gallery place, per
	`studio_tree`'s own "vendored Fusion is not needed by the gallery runtime
	path; skip" note) and is out of THIS task's class (a live "All controls"
	empty-mount defect), so it is left to whatever owns `src/`'s own package
	hygiene rather than smuggled into this guard's verdict.
]]

local fs = require("@lune/fs")
local studio_tree = require("./lib/studio_tree")

local checker = {}

export type Violation = {
	file: string, -- repo-relative source file
	scriptPath: string, -- the requiring script's Roblox instance path
	require: string, -- the literal require() string
	reason: string,
}

export type Options = {
	-- inject a synthetic module-scope require for the negative-control proof
	injectFile: string?,
	injectLine: string?,
}

-- Resolves `reqPath` (a literal relative require string) against `scriptPath`
-- (the requiring script's OWN Roblox instance path), using the same popping
-- rule live Rojo/Studio uses for `require("../foo")`: start at the script's
-- PARENT (one implicit pop — a bare "./x" means "my sibling x"), then each
-- "../" pops one more level, and running out of levels is exactly the engine's
-- own "could not get parent of component '..'" error.
local function resolveRelative(scriptPath: string, reqPath: string): (string?, string?)
	local segs: { string } = {}
	for seg in string.gmatch(scriptPath, "[^%.]+") do
		table.insert(segs, seg)
	end
	table.remove(segs) -- pop the script's own name: now "parent of the script"

	for tok in string.gmatch(reqPath, "[^/]+") do
		if tok == "." then
			-- stay at the current directory
		elseif tok == ".." then
			if #segs == 0 then
				return nil, `could not get parent of component ".."`
			end
			table.remove(segs)
		else
			table.insert(segs, tok)
		end
	end
	return table.concat(segs, "."), nil
end

function checker.check(
	opts: Options?
): { ok: boolean, violations: { Violation }, counts: { files: number, requiresChecked: number } }
	local options = opts or {}
	local entries = studio_tree.entries("gallery")

	local existing: { [string]: boolean } = {}
	for _, e in entries do
		existing[e.path] = true
	end

	local violations: { Violation } = {}
	local filesChecked = 0
	local requiresChecked = 0

	for _, e in entries do
		-- SCANNED (not targeted): skip `src/`'s own files (`ReplicatedStorage.
		-- Facet` and its descendants) — see the module header for the one known,
		-- inert, out-of-class exception this excludes (`fusion_adapter.luau`'s
		-- vendored-Fusion reach). They still count as valid TARGETS via
		-- `existing` above.
		local isSrc = e.path == "ReplicatedStorage.Facet" or string.match(e.path, "^ReplicatedStorage%.Facet%.") ~= nil
		if e.file == "" or isSrc then
			continue
		end
		filesChecked += 1
		local source = fs.readFile(e.file)
		if options.injectFile == e.file and options.injectLine ~= nil then
			source ..= "\n" .. options.injectLine .. "\n"
		end
		for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
			-- module scope only: a guarded fallback (the safe idiom) is always
			-- indented inside a pcall/function body, never at column 0
			if string.match(line, "^%s") ~= nil or line == "" then
				continue
			end
			local reqPath = string.match(line, "require%([\"'](%.[^\"']*)[\"']%)")
			if reqPath == nil then
				continue
			end
			requiresChecked += 1
			local resolved, err = resolveRelative(e.path, reqPath)
			if resolved == nil then
				table.insert(violations, {
					file = e.file,
					scriptPath = e.path,
					require = reqPath,
					reason = err :: string,
				})
			elseif not existing[resolved] then
				table.insert(violations, {
					file = e.file,
					scriptPath = e.path,
					require = reqPath,
					reason = `resolves to '{resolved}', which does not exist in the Studio instance tree`,
				})
			end
		end
	end

	return {
		ok = #violations == 0,
		violations = violations,
		counts = { files = filesChecked, requiresChecked = requiresChecked },
	}
end

return checker
