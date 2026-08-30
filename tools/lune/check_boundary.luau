--!strict
-- Client/server boundary static check (UI-BOUND-001, design §4.1): walks the
-- require graph of src/ and fails if
--   (a) any module OUTSIDE src/client requires a module under src/client
--       (the client renderer/platform layer must be unreachable from
--       shared/server-visible code), or
--   (b) any module under src/core, src/replication, or src/shared requires
--       the engine-only areas of the vendored Fusion copy (RobloxExternal,
--       Instances) or the vendor root init (which pulls them in).
--
-- ...and then walks the CONSUMER side (ENF-2). ADR-0011 tells a game to reach
-- Facet through the root module plus a short list of client entry points, and
-- nothing else — but nothing checked it, so the rule lived only in prose. Rule
--   (c) a require in the game or in examples/ that names a Facet module by
--       INSTANCE PATH (`require(ReplicatedStorage.Facet.<...>.<module>)`)
--       must land on a BLESSED client entry point. Requiring the Facet root
--       is always legal; reaching past it into `core`, `render`, `layout`,
--       `controls` … is the "features usable only via internal imports" class,
--       and it is what makes an internal rename a consumer break.
-- Writes artifacts/boundary.json. Exit 0 only with zero violations.

local fs = require("@lune/fs")
local process = require("@lune/process")
local artifact = require("./artifact")

local violations: { { file: string, target: string, rule: string } } = {}
local scanned = 0

local function normalize(path: string): string
	local parts = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local function checkFile(filePath: string)
	scanned += 1
	local dir = string.match(filePath, "^(.*)/[^/]+$") or ""
	local isInit = string.match(filePath, "init%.luau$") ~= nil
	local insideClient = string.match(filePath, "^src/client/") ~= nil
	local engineFreeZone = string.match(filePath, "^src/core/") ~= nil
		or string.match(filePath, "^src/replication/") ~= nil
		or string.match(filePath, "^src/shared/") ~= nil
		or string.match(filePath, "^src/preview/") ~= nil
	for target in string.gmatch(fs.readFile(filePath), [[require%(%s*"([^"]+)"%s*%)]]) do
		local resolvedBase: string
		if string.sub(target, 1, 6) == "@self/" then
			resolvedBase = if isInit then dir .. "/" .. string.sub(target, 7) else dir .. "/" .. string.sub(target, 7)
		elseif target == "@self" then
			--[[ THE SAME ROOT, SPELLED THE OTHER WAY (rule (d) below). Bare
				`@self` is Lune's alias for the containing library's root, and this
				walk only ever visits `src/`, so that root is `src` whatever
				directory the file sits in. Only `src/init.luau` uses the `@self/`
				form today, which is why the prefix branch above resolves it against
				`dir` and has never had to answer this question. ]]
			resolvedBase = "src"
		elseif string.sub(target, 1, 1) == "@" then
			continue -- runtime alias (@lune etc.)
		else
			-- init.luau's "./" means siblings of its directory-module
			local base = if isInit then (string.match(dir, "^(.*)/[^/]+$") or "") else dir
			resolvedBase = base .. "/" .. target
		end
		local resolved = normalize(resolvedBase)
		--[[ (d) NOTHING UNDER src/ MAY REQUIRE THE LIBRARY ROOT (2026-08-21).

			`src/init.luau` requires every control module near its top and only
			assembles its exports ~470 lines later, so a module it pulls in that
			requires the root back is a cycle — and Lune does not report a cycle.
			It HANGS: no output, no stack, no timeout, forever. Measured with a
			two-module cycle and killed at 15 seconds with an empty transcript.

			That is the worst failure this repository can hand a newcomer, and it
			handed one exactly that: `docs/extending/new-control.md` showed
			`Facet.specGuard.<...>` at module scope as the in-repo pattern, a
			fresh-context author wrote it literally, and `lune run tests/run_one`
			hung with nothing to pull on. All 24 shipped controls reach the same
			implementation through `require("../spec_guard")`.

			So the guard is STATIC. The hang happens inside Lune's own resolver
			before a single line of ours runs, so no runtime check in `spec_guard`
			or `init` can ever see it — but the require is right there in the
			source, and a checker that already walks every require can refuse it
			by name in under a second. ]]
		if resolved == "src" then
			table.insert(violations, { file = filePath, target = resolved, rule = "src-module-requires-library-root" })
		end
		if not insideClient and string.match(resolved, "^src/client/") then
			table.insert(violations, { file = filePath, target = resolved, rule = "non-client-requires-client" })
		end
		if
			engineFreeZone
			and (
				string.match(resolved, "^vendor/Fusion/RobloxExternal")
				or string.match(resolved, "^vendor/Fusion/Instances/")
				or resolved == "vendor/Fusion"
			)
		then
			table.insert(
				violations,
				{ file = filePath, target = resolved, rule = "engine-free-zone-requires-engine-vendor" }
			)
		end
	end
end

local function walk(dir: string)
	if not fs.isDir(dir) then
		return
	end
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walk(path)
		elseif string.match(name, "%.luau$") then
			checkFile(path)
		end
	end
end

walk("src")

-- ---------------------------------------------------------------------------
-- (c) CONSUMER SCAN (ENF-2). The blessed client entry points: everything else
-- under the Facet tree is internal, and a consumer reaching it is a boundary
-- violation whether or not it currently works. Pinned in api.md's client
-- entry-point section and in ADR-0011 — this is the same list, mechanically.
local BLESSED_CLIENT_MODULES: { [string]: boolean } = {
	--[[ BLESSED 0.10.0 (REUSE-109), and the first entry a consumer should reach
		for: `host.new` composes `roblox_env` + `screen_target` + `roblox_input` +
		the presenter into the one bootstrap, and drives BOTH halves of the frame.
		There was no framework host, so all eight known bootstraps were hand-rolled
		and three of the four shipped ones drove `refresh()` without `tick(dt)` —
		a frozen motion clock that no dump can distinguish from a settled one. ]]
	host = true,
	screen_target = true,
	roblox_env = true,
	roblox_input = true,
	roblox_resources = true,
	billboard_target = true,
	-- the world surface (ADR-0063, 2026-08-29): flat Facet on a SurfaceGui a
	-- player walks up to. Blessed for the same reason its two siblings are — a
	-- render target is required directly and never exported from the Facet table.
	surface_target = true,
	theme_controller = true,
	edit_preview = true,
	motion_driver = true,
	-- the opt-in, default-off haptics adapter (round 2 §3.3). Blessed because a
	-- game switching haptics on requires it directly, exactly as it requires
	-- `motion_driver` — and because it must never be reachable any other way:
	-- nothing in `src/` outside `src/client/` requires it, which is what keeps
	-- "Facet plays nothing" true of the shared/server graph.
	haptics = true,
	--[[ BLESSED 2026-08-17 (MAINT-7), because the guide already taught them and
		neither has a blessed route.

		`docs/guide/07-input.md` tells a consumer to require both of these
		DIRECTLY — the legacy-control disable and its two contention probes, and
		the touch-controls suppression an exclusive surface needs — while this
		checker refused the same require for every consumer outside `examples/`.
		One of the two had to move, and it could not be the guide: both are
		engine-level side effects the engine-free presenter structurally cannot
		perform, so there is no `Facet.*` route to send an author to instead. They
		are blessed as what they already are: narrow, client-only, documented in
		api.md §Client entry points with the same compatibility promise as the
		other nine. ]]
	gamepad_contention = true,
	responder_effects = true,
}

-- consumer trees, relative to the library root. The game is the production
-- consumer; examples/ is the one that ships inside this repository.
local CONSUMER_ROOTS = {
	"../../../games/RascalRally/code/src",
	"examples",
}

-- IN-REPO HARNESS EXEMPTIONS, named with their reason. `examples/` is not an
-- out-of-repo consumer: the gallery is this library's own drive harness, and a
-- few of its scenarios exist precisely to exercise an INTERNAL seam on a device.
-- Each is listed so the rule ships ENFORCING while the reach is explicit rather
-- than silently tolerated — the same shape as check_registration's PROOF_GAPS.
-- Nothing here applies outside `examples/`: a game reaching any of these is a
-- violation. Remove an entry the moment the seam is promoted or the scenario
-- moves onto the public surface.
local EXAMPLE_INTERNAL_REACH: { [string]: string } = {
	text_calibration = "the text-measurement lab drives the calibration module directly; it has no public surface (PKT-5 class)",
	text_metrics = "the same lab reads the estimator's own bounds to compare them against the engine's",
	text_premeasure = "the lab drives the premeasurement task directly to prove the two-read correction on a device",
	-- `gamepad_contention` and `responder_effects` were here, each with the reason
	-- "not yet a blessed entry point" — a promise with no date and no owner
	-- (MAINT-22). Both are blessed now (see BLESSED_CLIENT_MODULES above), so the
	-- exemptions are gone rather than reworded.
	profile = "the performance lab opens the framework's OWN balanced MicroProfiler span wrapper, so the scenario driver's scopes and Facet's phases come from one implementation and cannot disagree about naming or balance (roadmap Step 9, PLN-2)",
}

local consumerScanned = 0

-- `:WaitForChild("x")` / `:FindFirstChild("x")` / `["x"]` all mean `.x` here
local function normalizeIndexing(text: string): string
	local out = string.gsub(text, "[%.:]%s*WaitForChild%s*%(%s*[\"']([%w_]+)[\"']%s*%)", ".%1")
	out = string.gsub(out, "[%.:]%s*FindFirstChild%s*%(%s*[\"']([%w_]+)[\"']%s*%)", ".%1")
	out = string.gsub(out, "%[%s*[\"']([%w_]+)[\"']%s*%]", ".%1")
	return out
end

-- where the WHOLE identifier `Facet` appears in already-normalized text, or nil.
-- Whole-identifier, because the gallery replicates sibling folders whose names
-- START with it — `FacetThemes`, `FacetScenarios`, `FacetExamples` — and a
-- substring match reads `FindFirstChild("FacetScenarios")` as the library root
-- with a stray `Themes`/`Scenarios` path component hanging off it.
local function findRootToken(normalized: string): number?
	local from = 1
	while true do
		local s, e = string.find(normalized, "Facet", from, true)
		if s == nil then
			return nil
		end
		local before = if s > 1 then string.sub(normalized, s - 1, s - 1) else ""
		local after = string.sub(normalized, (e :: number) + 1, (e :: number) + 1)
		if not string.match(before, "[%w_]") and not string.match(after, "[%w_]") then
			return e :: number
		end
		from = (e :: number) + 1
	end
end

-- HOISTED ROOTS (ARCH-6). The scan used to inspect only require expressions whose
-- TEXT contained "Facet", which is defeated by the single most likely real-world
-- spelling — and the one the production game already uses:
--
--   local root = ReplicatedStorage:WaitForChild("Facet")
--   require(root.render.renderer)      -- text has no "Facet"; missed entirely
--
-- So a local whose right-hand side names Facet MARKS that variable, and a
-- require through a marked variable is resolved to the same Facet-relative path
-- and judged by the same blessed list. Requiring the ROOT through a marked
-- variable (`require(root)`) stays legal — that is the documented entry point,
-- and it is exactly what the game does.
--
-- Marking is transitive through pure index chains (`local c = root.client`) but
-- deliberately NOT through `require(...)`: `local Facet = require(root)` yields
-- the library TABLE, whose fields are values rather than module instances.
local function markedRoots(source: string): { [string]: boolean }
	-- a chained call broken across lines is one statement for our purposes
	local joined = string.gsub(source, "\n%s*([%.:])", "%1")
	local marked: { [string]: boolean } = {}
	local changed = true
	while changed do
		changed = false
		for name, rhs in string.gmatch(joined, "([%w_]+)%s*=%s*([^\n]*)") do
			if marked[name] then
				continue
			end
			local normalizedRhs = normalizeIndexing(rhs)
			local namesRoot = findRootToken(normalizedRhs) ~= nil
			local viaMarked = false
			if not namesRoot and string.find(rhs, "require", 1, true) == nil then
				local head = string.match(normalizedRhs, "^%s*([%w_]+)%s*%.")
				viaMarked = head ~= nil and marked[head] == true
			end
			if namesRoot or viaMarked then
				marked[name] = true
				changed = true
			end
		end
	end
	return marked
end

-- the Facet-relative path a require expression reaches, or nil when the
-- expression is not a Facet instance-path require at all
local function facetPath(expr: string, marked: { [string]: boolean }): { string }?
	local normalized = normalizeIndexing(expr)
	local tail: string? = nil
	local rootEnd = findRootToken(normalized)
	if rootEnd ~= nil then
		tail = string.sub(normalized, rootEnd + 1)
	else
		local inner = string.match(normalized, "^require%s*%((.*)%)$")
		local head = if inner ~= nil then string.match(inner, "^%s*([%w_]+)") else nil
		if head == nil or not marked[head :: string] then
			return nil
		end
		local from = string.find(inner :: string, head :: string, 1, true) :: number
		tail = string.sub(inner :: string, from + #(head :: string))
	end
	local components: { string } = {}
	for component in string.gmatch(tail :: string, "%.([%w_]+)") do
		table.insert(components, component)
	end
	return components
end

-- pure over (path, source) so the rule can be mutation-tested below without
-- writing a synthetic tree to disk
local function consumerViolations(filePath: string, source: string): { { file: string, target: string, rule: string } }
	local found: { { file: string, target: string, rule: string } } = {}
	local marked = markedRoots(source)
	for expr in string.gmatch(source, "require%b()") do
		local components = facetPath(expr, marked)
		if components == nil or #components == 0 then
			continue -- not a Facet path, or the Facet root module itself (legal)
		end
		local module = components[#components]
		local exempt = string.sub(filePath, 1, 9) == "examples/" and EXAMPLE_INTERNAL_REACH[module] ~= nil
		if not BLESSED_CLIENT_MODULES[module] and not exempt then
			table.insert(found, {
				file = filePath,
				target = "Facet." .. table.concat(components, "."),
				rule = "consumer-requires-facet-internal",
			})
		end
	end
	return found
end

local function checkConsumerFile(filePath: string)
	consumerScanned += 1
	for _, v in consumerViolations(filePath, fs.readFile(filePath)) do
		table.insert(violations, v)
	end
end

local function walkConsumer(dir: string)
	if not fs.isDir(dir) then
		return
	end
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			walkConsumer(path)
		elseif string.match(name, "%.luau$") then
			checkConsumerFile(path)
		end
	end
end

for _, root in CONSUMER_ROOTS do
	walkConsumer(root)
end

-- A SCAN THAT FOUND NOTHING IS NOT A PASS (ARCH-6). `walkConsumer` returns
-- silently when a root does not resolve, so a moved game tree (or a checker run
-- from the wrong cwd) reported "PASS, 0 consumer files" and the whole ENF-2 half
-- of this check evaporated without a word.
if consumerScanned == 0 then
	print(
		`boundary: FAIL — consumer scan found no files — the game tree moved? (roots: {table.concat(
			CONSUMER_ROOTS,
			", "
		)})`
	)
	process.exit(1)
end

-- ...AND THE RULE MUST BITE (ARCH-6). The hoisted-root form was live-defeated for
-- the life of this checker, under a green run, because nothing ever asked the rule
-- to refuse anything. These four synthetic sources are the mutation test, run on
-- every invocation: two spellings that MUST be caught, and the two legal forms
-- that must stay legal — including the one the production game uses.
local SELF_TEST: { { name: string, source: string, expect: string? } } = {
	{
		name = "hoisted root, dot path",
		source = 'local root = ReplicatedStorage:WaitForChild("Facet")\nlocal r = require(root.render.renderer)',
		expect = "Facet.render.renderer",
	},
	{
		name = "hoisted root, WaitForChild chain",
		source = "local root = ReplicatedStorage.Facet\n"
			.. 'local s = require(root:WaitForChild("layout"):WaitForChild("solver"))',
		expect = "Facet.layout.solver",
	},
	{
		name = "hoisted root, required as the ROOT (the game's own spelling)",
		source = 'local root = ReplicatedStorage:WaitForChild("Facet")\nlocal Facet = require(root)',
		expect = nil,
	},
	{
		name = "hoisted root, blessed client entry point",
		source = 'local root = ReplicatedStorage:WaitForChild("Facet")\n'
			.. "local st = require(root.client.screen_target)",
		expect = nil,
	},
}
for _, case in SELF_TEST do
	local found = consumerViolations("selftest/case.luau", case.source)
	local got = if #found > 0 then found[1].target else nil
	if got ~= case.expect then
		print(
			`boundary: FAIL — the consumer rule does not bite: case '{case.name}' expected `
				.. `{case.expect or "no violation"}, got {got or "no violation"}`
		)
		process.exit(1)
	end
end

artifact.writeJson("artifacts/boundary.json", {
	schema = "facet-boundary/1",
	status = if #violations == 0 then "PASS" else "FAIL",
	requirement = "UI-BOUND-001",
	scannedFiles = scanned,
	consumerScannedFiles = consumerScanned,
	blessedClientModules = BLESSED_CLIENT_MODULES,
	rules = {
		"non-client-requires-client",
		"engine-free-zone-requires-engine-vendor",
		"consumer-requires-facet-internal",
	},
	violations = violations,
})
for _, v in violations do
	print(`  VIOLATION [{v.rule}] {v.file} -> {v.target}`)
end
print(
	`boundary: {#violations == 0 and "PASS" or "FAIL"} ({scanned} src files, {consumerScanned} consumer files) -> artifacts/boundary.json`
)
process.exit(if #violations == 0 then 0 else 1)
