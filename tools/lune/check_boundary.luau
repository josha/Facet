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
-- LuauUI through the root module plus a short list of client entry points, and
-- nothing else — but nothing checked it, so the rule lived only in prose. Rule
--   (c) a require in the game or in examples/ that names a LuauUI module by
--       INSTANCE PATH (`require(ReplicatedStorage.LuauUI.<...>.<module>)`)
--       must land on a BLESSED client entry point. Requiring the LuauUI root
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
		elseif string.sub(target, 1, 1) == "@" then
			continue -- runtime alias (@lune etc.)
		else
			-- init.luau's "./" means siblings of its directory-module
			local base = if isInit then (string.match(dir, "^(.*)/[^/]+$") or "") else dir
			resolvedBase = base .. "/" .. target
		end
		local resolved = normalize(resolvedBase)
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
-- under the LuauUI tree is internal, and a consumer reaching it is a boundary
-- violation whether or not it currently works. Pinned in api.md's client
-- entry-point section and in ADR-0011 — this is the same list, mechanically.
local BLESSED_CLIENT_MODULES: { [string]: boolean } = {
	screen_target = true,
	roblox_env = true,
	roblox_input = true,
	roblox_resources = true,
	billboard_target = true,
	theme_controller = true,
	edit_preview = true,
	motion_driver = true,
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
	gamepad_contention = "the gallery demonstrates the legacy-control disable seam documented in docs/guide/07-input.md; not yet a blessed entry point",
	responder_effects = "the gallery binds the responder-effects seam the guide teaches; not yet a blessed entry point",
}

local consumerScanned = 0

local function checkConsumerFile(filePath: string)
	consumerScanned += 1
	local source = fs.readFile(filePath)
	for expr in string.gmatch(source, "require%b()") do
		local at = string.find(expr, "LuauUI", 1, true)
		if at == nil then
			continue
		end
		-- normalise `:WaitForChild("x")` into `.x`, then read the path components
		-- that follow the LuauUI root
		local tail = string.sub(expr, at + 6)
		tail = string.gsub(tail, "[%.:]%s*WaitForChild%s*%(%s*[\"']([%w_]+)[\"']%s*%)", ".%1")
		tail = string.gsub(tail, "%[%s*[\"']([%w_]+)[\"']%s*%]", ".%1")
		local components: { string } = {}
		for component in string.gmatch(tail, "%.([%w_]+)") do
			table.insert(components, component)
		end
		if #components == 0 then
			continue -- the LuauUI root module itself: always legal
		end
		local module = components[#components]
		local exempt = string.sub(filePath, 1, 9) == "examples/" and EXAMPLE_INTERNAL_REACH[module] ~= nil
		if not BLESSED_CLIENT_MODULES[module] and not exempt then
			table.insert(violations, {
				file = filePath,
				target = "LuauUI." .. table.concat(components, "."),
				rule = "consumer-requires-luauui-internal",
			})
		end
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

artifact.writeJson("artifacts/boundary.json", {
	schema = "luauui-boundary/1",
	status = if #violations == 0 then "PASS" else "FAIL",
	requirement = "UI-BOUND-001",
	scannedFiles = scanned,
	consumerScannedFiles = consumerScanned,
	blessedClientModules = BLESSED_CLIENT_MODULES,
	rules = {
		"non-client-requires-client",
		"engine-free-zone-requires-engine-vendor",
		"consumer-requires-luauui-internal",
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
