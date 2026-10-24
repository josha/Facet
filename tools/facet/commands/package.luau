--!strict
local Gate = require("../lib/gate")
local Verify = require("../../vendor/verify/src/core")

local stringext = require("@std/stringext")
local Assets = require("../lib/assets")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Hash = require("../lib/hash")
local Json = require("../lib/json")
local Model = require("../lib/model")
local Rule = require("../lib/rule")
local Run = require("../lib/run")
local Snapshot = require("../lib/snapshot")
local purity = require("../checks/library_purity")

local USAGE = [[usage: lute run tools/facet package <command> [options]

The maintainer interface to Facet's Roblox Package release channel. Git is
canonical: the version, the commit and the source hash come from the repository.

commands:
  stage [--out DIR] [--quiet]                    stage the Distribution folder
  manifest --model XML --artifact FILE --out M   write the semantic manifest
  build [--publisher] [--verify]                 rebuild build/Facet.rbxm and its manifest; --verify also inspects the package
  status                                         this tree against the last receipt
  verify [--skip-canary]                         build, tree inspection, purity, packaged canary
  create [release options]                       mint the asset (DRY RUN unless --confirm)
  publish [release options]                      push a revision (DRY RUN unless --confirm)
  rollback                                       print both rollback procedures; never uploads
  stamp --receipt R --studio-verified [--by NAME] [--notes TEXT]
  source-hash                                    print the source hash of src/
  --selftest                                     prove every refusal and drive a fake transport

release options: --confirm --route studio|open-cloud --allow-route-override
  --version X.Y.Z --commit SHA --asset-id ID --creator-id ID --creator-type user|group
  --actor NAME --baseline-revision N --timeout SECONDS --poll SECONDS
global options: --config PATH --receipts DIR

ROBLOX_API_KEY is read from the environment only. It is never printed or written.
Exit codes: 0 success (a dry run included), 1 a refusal or a failed check,
2 an environment failure or a usage error.]]

local CANARY = "tools/engine/package_canary.luau"
local DEFAULT_CONFIG = "package/facet-package.json"
local DEFAULT_RECEIPTS = "package/receipts"
local GATE_EVIDENCE = "artifacts/verify/native/gate/latest.json"
local RBXM_CONTENT_TYPE = "model/x-rbxm"
local ASSET_TYPE = "Model"
local RECEIPT_SCHEMA = "facet-package-receipt/1"
local GATE_SCHEMA = "verify-gate/1"
local GATE_ID = "facet"
local REDACTED = "x-api-key: <redacted — never printed>"
local UNSET_ASSET = "<assetId — unset until create>"

local FORBIDDEN_SEGMENTS: { [string]: boolean } = {
	tests = true,
	examples = true,
	vendor = true,
	bench = true,
	spikes = true,
}
local FORBIDDEN_SUBSTRINGS: { string } = { "fusion_adapter", "imperative", ".verify" }
local APPROVED_MODERATION: { [string]: boolean } = { Approved = true, MODERATION_STATE_APPROVED = true }
local REQUIRED_DISTRIBUTION: { { string } } = {
	{ "Facet/Distribution", "Folder" },
	{ "Facet/Distribution/LICENSE", "StringValue" },
	{ "Facet/Distribution/THIRD_PARTY_NOTICES", "StringValue" },
}

local GUARDS: { { string } } = {
	{ "api key present (environment only)", "api-key-missing" },
	{ "working tree clean", "dirty-tree" },
	{ "--commit == HEAD", "commit-mismatch" },
	{ "--version == Facet.VERSION", "version-mismatch" },
	{ "fresh build matches the recorded manifest", "build-drift" },
	{ "creator configured", "creator-unset" },
	{ "creator argument matches config", "creator-mismatch" },
	{ "create only when no asset id exists", "asset-id-present" },
	{ "publish only when an asset id exists", "asset-id-missing" },
	{ "asset id argument matches config", "asset-id-mismatch" },
	{ "route override acknowledged", "route-override" },
	{ "release-gate evidence present", "gate-evidence-missing" },
	{ "release-gate evidence schema", "gate-evidence-schema" },
	{ "release-gate evidence is a release run", "gate-evidence-tier" },
	{ "release-gate evidence green", "gate-evidence-failed" },
	{ "release-gate ran on a clean tree", "gate-evidence-dirty" },
	{ "release-gate evidence attests this commit", "gate-evidence-commit" },
	{ "release-gate evidence attests this source", "gate-evidence-source" },
	{ "no operation in flight", "operation-in-flight" },
	{ "cloud revision not ahead of the receipts", "cloud-revision-newer" },
	{ "VERSION advanced under semver", "version-not-advanced" },
	{ "VERSION not reused with different source", "version-hash-conflict" },
	{ "moderation approved", "moderation-not-approved" },
}

type Gate = {
	schema: unknown,
	tier: unknown,
	status: unknown,
	commit: unknown,
	treeDirty: unknown,
	sourceHash: unknown,
	completedAt: unknown,
	runId: unknown?,
}

type Creator = { type: unknown, id: unknown }

type Cloud = { revisionId: unknown, revisionCreateTime: unknown }

type Facts = {
	op: string,
	apiKeyPresent: boolean,
	gitDirty: boolean,
	argCommit: string?,
	headCommit: string?,
	argVersion: string?,
	sourceVersion: string?,
	sourceHash: string?,
	freshBuildHash: string?,
	manifestHash: string?,
	configCreator: Creator,
	argCreatorType: string?,
	argCreatorId: unknown?,
	configAssetId: unknown?,
	argAssetId: unknown?,
	configRoute: string,
	argRoute: string?,
	allowRouteOverride: boolean,
	gate: Gate?,
	gatePath: string,
	latestReceipt: Json.Object?,
	cloudRevision: Cloud?,
	moderation: unknown?,
	manifest: Model.Manifest?,
}

type Refusal = { code: string, message: string }

type Verdict = { refusals: { Refusal }, evaluated: { [string]: boolean } }

type Decide = (Facts) -> Verdict

type Arguments = {
	confirm: boolean,
	route: string?,
	allowRouteOverride: boolean,
	version: string?,
	commit: string?,
	assetId: string?,
	creatorId: string?,
	creatorType: string?,
	actor: string?,
	baselineRevision: string?,
	timeout: number,
	poll: number,
}

type Environment = {
	root: string,
	config: string,
	receipts: string,
	gate: string,
	model: string,
	xml: string,
	manifest: string,
	publisher: string,
	transport: Assets.Transport,
	decide: Decide,
	apiKey: () -> string?,
	build: (publisher: boolean) -> Model.Manifest,
	toolchain: () -> Json.Object,
	clock: Assets.Clock,
	say: (string) -> (),
}

type Stored = { path: string, receipt: Json.Object }

local stopCode = 1

local function stop(code: number, message: string?): never
	stopCode = code
	error(message or "", 0)
end

local function guarded(say: (string) -> (), body: () -> number): number
	stopCode = 1
	local ok, result = pcall(body)
	if ok then
		return result
	end
	local message = tostring(result)
	if message ~= "" then
		say(message)
	end
	return stopCode
end

local function nullable(value: unknown): unknown
	if value == nil then
		return Json.null
	end
	return value
end

local function raw(value: unknown, key: string): unknown
	local object = Json.asObject(value)
	if object == nil then
		return nil
	end
	return object[key]
end

local function truthy(value: unknown): boolean
	if value == nil or value == false or value == 0 or value == "" or Json.isNull(value) then
		return false
	end
	if type(value) == "table" then
		return next(value :: { [unknown]: unknown }) ~= nil
	end
	return true
end

local function quoted(text: string): string
	local quote = if string.find(text, "'", 1, true) ~= nil and string.find(text, '"', 1, true) == nil then '"' else "'"
	local escaped = string.gsub(text, "[%c\\'\"]", function(char: string): string
		if char == "\\" then
			return "\\\\"
		elseif char == quote then
			return "\\" .. char
		elseif char == "'" or char == '"' then
			return char
		elseif char == "\n" then
			return "\\n"
		elseif char == "\r" then
			return "\\r"
		elseif char == "\t" then
			return "\\t"
		end
		return ("\\x%02x"):format(string.byte(char))
	end)
	return quote .. escaped .. quote
end

local repr: (unknown) -> string

local function str(value: unknown): string
	if value == nil or Json.isNull(value) then
		return "None"
	elseif value == true then
		return "True"
	elseif value == false then
		return "False"
	elseif type(value) == "number" then
		if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
			return ("%d"):format(value)
		end
		return tostring(value)
	elseif type(value) == "string" then
		return value
	end
	return repr(value)
end

repr = function(value: unknown): string
	if type(value) == "string" then
		return quoted(value)
	end
	local object = Json.asObject(value)
	if object ~= nil then
		local parts: { string } = {}
		for _, key in Json.keys(object) do
			table.insert(parts, quoted(key) .. ": " .. repr(object[key]))
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	local array = Json.asArray(value)
	if array ~= nil then
		local parts: { string } = {}
		for _, item in array do
			table.insert(parts, repr(item))
		end
		return "[" .. table.concat(parts, ", ") .. "]"
	end
	return str(value)
end

local function prefix(value: unknown, length: number): string
	return string.sub(str(value), 1, length)
end

local function lastSegment(value: string): string
	local segments = string.split(value, "/")
	return segments[#segments]
end

local function semver(value: unknown): { number }?
	local text = if truthy(value) then str(value) else ""
	local major, minor, patch = string.match(text, "^(%d+)%.(%d+)%.(%d+)")
	if major == nil or minor == nil or patch == nil then
		return nil
	end
	return { tonumber(major) or 0, tonumber(minor) or 0, tonumber(patch) or 0 }
end

local function compareVersions(left: { number }, right: { number }): number
	for index = 1, 3 do
		if left[index] ~= right[index] then
			return if left[index] < right[index] then -1 else 1
		end
	end
	return 0
end

local function nowIso(): string
	return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function ordered(entries: { { unknown } }): Json.Object
	local object = Json.object()
	for _, entry in entries do
		local key = entry[1]
		if type(key) == "string" then
			Json.set(object, key, nullable(entry[2]))
		end
	end
	return object
end

local function git(root: string, arguments: { string }): string
	local result = Run.git(arguments, root)
	if not result.ok then
		stop(1, ("package: git %s failed: %s"):format(table.concat(arguments, " "), stringext.trim(result.stderr)))
	end
	return stringext.trim(result.stdout)
end

local function porcelain(root: string, paths: { string }?): string
	local arguments = { "status", "--porcelain" }
	if paths ~= nil and #paths > 0 then
		table.insert(arguments, "--")
		for _, path in paths do
			table.insert(arguments, path)
		end
	end
	return git(root, arguments)
end

local function versionOf(tool: string): string
	local result = Run.capture({ tool, "--version" })
	local out = stringext.trim(result.stdout)
	if out ~= "" then
		return out
	end
	local err = stringext.trim(result.stderr)
	if err ~= "" and string.sub(err, 1, 16) ~= "could not start " then
		return err
	end
	return "unknown"
end

local function toolchain(): Json.Object
	return ordered({ { "rojo", versionOf("rojo") }, { "lute", versionOf("lute") } })
end

local function readGateEvidence(path: string): Gate?
	if not Files.isFile(path) then
		return nil
	end
	local decoded, problem = Json.tryDecode(Files.read(path))
	if problem ~= nil then
		return nil
	end
	local outcome = Json.asObject(decoded)
	if outcome == nil then
		return nil
	end
	local acceptance = Json.objectField(outcome, "acceptance")
	local build = Json.objectField(outcome, "build")
	if acceptance == nil or build == nil or Json.field(outcome, "gate") ~= GATE_ID then
		return nil
	end
	return {
		schema = "verify-gate/" .. str(raw(outcome, "schemaVersion")),
		tier = if Json.field(acceptance, "complete") == true then "release" else "selected",
		status = if Json.field(acceptance, "releasable") == true then "PASS" else str(raw(acceptance, "verdict")),
		commit = Json.field(build, "commit"),
		treeDirty = Json.field(build, "clean") ~= true,
		sourceHash = Json.field(build, "digest"),
		completedAt = os.date("!%Y-%m-%dT%H:%M:%SZ", math.floor(Files.modifiedSeconds(path))),
		runId = Json.field(outcome, "runId"),
	}
end

local function loadConfig(path: string): Json.Object
	if not Files.isFile(path) then
		stop(1, "package: no config at " .. path)
	end
	local decoded, problem = Json.tryDecode(Files.read(path))
	if problem ~= nil then
		stop(1, ("package: %s is not JSON: %s"):format(path, problem))
	end
	local config = Json.asObject(decoded)
	if config == nil then
		return stop(1, ("package: %s is not a JSON object"):format(path))
	end
	return config
end

local function saveConfig(path: string, config: Json.Object)
	Files.writeAtomic(path, Json.pretty(config))
end

local function receipts(directory: string): { Stored }
	local found: { Stored } = {}
	for _, entry in Files.list(directory) do
		if string.sub(entry.name, -5) ~= ".json" then
			continue
		end
		local path = Files.join(directory, entry.name)
		if not Files.isFile(path) then
			continue
		end
		local decoded, problem = Json.tryDecode(Files.read(path))
		local receipt = Json.asObject(decoded)
		if problem == nil and receipt ~= nil then
			table.insert(found, { path = path, receipt = receipt })
		end
	end
	local order: { [Stored]: number } = {}
	for index, stored in found do
		order[stored] = index
	end
	local function published(stored: Stored): string
		local value = raw(stored.receipt, "publishedAt")
		return if truthy(value) then str(value) else ""
	end
	table.sort(found, function(left: Stored, right: Stored): boolean
		local a, b = published(left), published(right)
		if a ~= b then
			return a < b
		end
		return order[left] < order[right]
	end)
	return found
end

local function latestReceipt(directory: string): Json.Object?
	local found = receipts(directory)
	if #found == 0 then
		return nil
	end
	return found[#found].receipt
end

local function decide(facts: Facts): Verdict
	local refusals: { Refusal } = {}
	local evaluated: { [string]: boolean } = {}
	local function mark(...: string)
		for _, code in { ... } do
			evaluated[code] = true
		end
	end
	local function refuse(code: string, message: string)
		evaluated[code] = true
		table.insert(refusals, { code = code, message = message })
	end

	mark("api-key-missing", "dirty-tree", "commit-mismatch", "version-mismatch", "build-drift", "creator-unset")
	if not facts.apiKeyPresent then
		refuse(
			"api-key-missing",
			"ROBLOX_API_KEY is not set in the environment. It is read from the environment ONLY — never a keys file, never a cookie — and it is never printed or written to a receipt."
		)
	end

	if facts.gitDirty then
		refuse("dirty-tree", "the working tree has uncommitted changes; a release must be an exact commit")
	end

	local argCommit = facts.argCommit
	if not truthy(argCommit) then
		refuse("commit-mismatch", "--commit <sha> is required and must equal HEAD")
	elseif argCommit ~= facts.headCommit then
		refuse("commit-mismatch", ("--commit %s is not HEAD (%s)"):format(str(argCommit), str(facts.headCommit)))
	end

	local argVersion = facts.argVersion
	if not truthy(argVersion) then
		refuse("version-mismatch", "--version <x.y.z> is required and must equal Facet.VERSION")
	elseif argVersion ~= facts.sourceVersion then
		refuse(
			"version-mismatch",
			("--version %s is not Facet.VERSION (%s)"):format(str(argVersion), str(facts.sourceVersion))
		)
	end

	if facts.manifestHash == nil then
		refuse(
			"build-drift",
			"there is no build/Facet.manifest.json to compare against; run `lute run tools/facet package build` (or `verify`) so there is a recorded build of this tree"
		)
	elseif facts.freshBuildHash ~= facts.manifestHash then
		refuse(
			"build-drift",
			("a fresh build hashes %s but build/Facet.manifest.json records %s; the recorded manifest is stale"):format(
				str(facts.freshBuildHash),
				str(facts.manifestHash)
			)
		)
	end

	local creator = facts.configCreator
	if not truthy(creator.type) or not truthy(creator.id) then
		refuse("creator-unset", "package/facet-package.json has no creator; it is filled at the owner checkpoint")
	else
		if truthy(facts.argCreatorType) or truthy(facts.argCreatorId) then
			mark("creator-mismatch")
		end
		if truthy(facts.argCreatorType) and facts.argCreatorType ~= creator.type then
			refuse(
				"creator-mismatch",
				("--creator-type %s != configured %s"):format(str(facts.argCreatorType), str(creator.type))
			)
		end
		if truthy(facts.argCreatorId) and str(facts.argCreatorId) ~= str(creator.id) then
			refuse(
				"creator-mismatch",
				("--creator-id %s != configured %s"):format(str(facts.argCreatorId), str(creator.id))
			)
		end
	end

	local configAsset = facts.configAssetId
	local argAsset = facts.argAssetId
	if facts.op == "create" then
		mark("asset-id-present")
		if truthy(configAsset) then
			refuse(
				"asset-id-present",
				("package/facet-package.json already records assetId %s; create is one-time. Use publish to push a revision."):format(
					str(configAsset)
				)
			)
		end
	else
		mark("asset-id-missing")
		if not truthy(configAsset) then
			refuse("asset-id-missing", "package/facet-package.json records no assetId; run create first")
		elseif truthy(argAsset) then
			mark("asset-id-mismatch")
			if str(argAsset) ~= str(configAsset) then
				refuse("asset-id-mismatch", ("--asset-id %s != configured %s"):format(str(argAsset), str(configAsset)))
			end
		end
	end

	local argRoute = facts.argRoute
	if truthy(argRoute) and argRoute ~= facts.configRoute then
		mark("route-override")
		if not facts.allowRouteOverride then
			refuse(
				"route-override",
				("--route %s overrides the configured route %s; the configured route is explicit. Pass --allow-route-override to mean it."):format(
					str(argRoute),
					str(facts.configRoute)
				)
			)
		end
	end

	local gate = facts.gate
	mark("gate-evidence-missing")
	if gate == nil then
		refuse(
			"gate-evidence-missing",
			("no usable release-gate evidence at %s — the file must exist and carry a Verify gate outcome with its build binding; the release tier must run first"):format(
				facts.gatePath
			)
		)
	else
		mark(
			"gate-evidence-schema",
			"gate-evidence-tier",
			"gate-evidence-failed",
			"gate-evidence-dirty",
			"gate-evidence-source"
		)
		if gate.schema ~= GATE_SCHEMA then
			refuse(
				"gate-evidence-schema",
				("release-gate evidence declares schema %s, not %s"):format(repr(gate.schema), repr(GATE_SCHEMA))
			)
		end
		if gate.tier ~= "release" then
			refuse(
				"gate-evidence-tier",
				("release-gate evidence is for tier %s; only a `release` run authorizes a publish"):format(
					repr(gate.tier)
				)
			)
		end
		if gate.status ~= "PASS" then
			refuse("gate-evidence-failed", ("release-gate evidence status is %s, not PASS"):format(repr(gate.status)))
		end
		if gate.treeDirty ~= false then
			refuse(
				"gate-evidence-dirty",
				("release-gate evidence records treeDirty=%s; the gate must have run on a clean tree for its result to describe this commit"):format(
					repr(gate.treeDirty)
				)
			)
		end
		if truthy(argCommit) and argCommit == facts.headCommit then
			mark("gate-evidence-commit")
			if gate.commit ~= argCommit then
				refuse(
					"gate-evidence-commit",
					("release-gate evidence attests commit %s, not the %s being released"):format(
						str(gate.commit),
						str(argCommit)
					)
				)
			end
		end
		if gate.sourceHash ~= facts.sourceHash then
			refuse(
				"gate-evidence-source",
				("release-gate evidence attests source hash %s, but this tree hashes %s"):format(
					str(gate.sourceHash),
					str(facts.sourceHash)
				)
			)
		end
	end

	local receipt = facts.latestReceipt
	if truthy(receipt) then
		mark("operation-in-flight")
	end
	if
		receipt ~= nil
		and truthy(receipt)
		and truthy(raw(receipt, "operationPath"))
		and not truthy(raw(receipt, "assetRevision"))
	then
		refuse(
			"operation-in-flight",
			("receipt for %s records operation %s with no assetRevision; resolve that operation before starting another"):format(
				str(raw(receipt, "version")),
				str(raw(receipt, "operationPath"))
			)
		)
	end

	local cloud = facts.cloudRevision
	if cloud ~= nil and receipt ~= nil and truthy(receipt) then
		mark("cloud-revision-newer")
		local known = Json.field(Json.field(receipt, "assetRevision"), "revisionId")
		local seen = if Json.isNull(cloud.revisionId) then nil else cloud.revisionId
		if known == nil or (seen ~= nil and str(seen) ~= str(known)) then
			refuse(
				"cloud-revision-newer",
				("the cloud asset is at revision %s but the newest receipt knows %s; something published outside this tool"):format(
					str(seen),
					str(known)
				)
			)
		end
	end

	if receipt ~= nil and truthy(receipt) then
		local last = semver(raw(receipt, "version"))
		local current = semver(facts.sourceVersion)
		if last ~= nil and current ~= nil then
			mark("version-not-advanced", "version-hash-conflict")
			local order = compareVersions(current, last)
			if order < 0 then
				refuse(
					"version-not-advanced",
					("VERSION %s is behind the last receipt's %s"):format(
						str(facts.sourceVersion),
						str(raw(receipt, "version"))
					)
				)
			elseif order == 0 then
				if raw(receipt, "sourceHash") ~= facts.sourceHash then
					refuse(
						"version-hash-conflict",
						("VERSION %s was already published from source hash %s; this tree hashes %s"):format(
							str(facts.sourceVersion),
							str(raw(receipt, "sourceHash")),
							str(facts.sourceHash)
						)
					)
				else
					refuse(
						"version-not-advanced",
						("VERSION %s did not advance past the last receipt"):format(str(facts.sourceVersion))
					)
				end
			end
		end
	end

	local moderation = facts.moderation
	if moderation ~= nil and not Json.isNull(moderation) then
		mark("moderation-not-approved")
		if type(moderation) ~= "string" or not APPROVED_MODERATION[moderation] then
			refuse(
				"moderation-not-approved",
				("the asset's moderation state reads %s, not approved"):format(repr(moderation))
			)
		end
	end

	return { refusals = refusals, evaluated = evaluated }
end

local function expectedTree(root: string): ({ [string]: string }, { [string]: boolean })
	local modules: { [string]: string } = {}
	local folders: { [string]: boolean } = {}
	for _, relative in Model.sourceFiles(root) do
		local parts = string.split(relative, "/")
		local rest = table.move(parts, 2, #parts, 1, {})
		if #rest == 1 and rest[1] == "init.luau" then
			modules.Facet = relative
			continue
		end
		local accumulated = "Facet"
		for index = 1, #rest - 1 do
			accumulated ..= "/" .. rest[index]
			folders[accumulated] = true
		end
		local last = rest[#rest]
		local key = if last == "init.luau" then accumulated else accumulated .. "/" .. string.sub(last, 1, -6)
		modules[key] = relative
	end
	for path in modules do
		folders[path] = nil
	end
	return modules, folders
end

local function approvedVendorPaths(root: string): { [string]: boolean }
	local approved: { [string]: boolean } = { ["Facet/vendor"] = true, ["Facet/vendor/compose"] = true }
	local lock = Files.join(root, "src/vendor/compose/UPSTREAM.lock")
	local decoded = if Files.isFile(lock) then Json.tryDecode(Files.read(lock)) else nil
	local hashes = Json.objectField(decoded, "sha256")
	if hashes == nil then
		return approved
	end
	for _, name in Json.keys(hashes) do
		if string.sub(name, -5) ~= ".luau" then
			continue
		end
		local path = "Facet/vendor/compose/" .. string.sub(name, 1, -6)
		if string.sub(path, -5) == "/init" then
			path = string.sub(path, 1, -6)
		end
		while string.sub(path, 1, 13) == "Facet/vendor/" do
			approved[path] = true
			path = string.match(path, "^(.*)/[^/]*$") or ""
		end
	end
	return approved
end

local function sortedKeys<T>(map: { [string]: T }): { string }
	local keys: { string } = {}
	for key in map do
		table.insert(keys, key)
	end
	table.sort(keys)
	return keys
end

type Counts = { modules: number, folders: number, required: number, instances: number }

local function inspectTree(root: string, manifest: Model.Manifest): ({ string }, Counts)
	local modules, folders = expectedTree(root)
	local approved = approvedVendorPaths(root)
	local present: { [string]: Model.Instance } = {}
	for _, instance in manifest.instances do
		present[instance.path] = instance
	end
	local problems: { string } = {}
	for _, path in sortedKeys(modules) do
		local entry = present[path]
		if entry == nil then
			table.insert(problems, ("missing from the model: %s (from %s)"):format(path, modules[path]))
		elseif entry.className ~= "ModuleScript" then
			table.insert(problems, ("%s is a %s, not a ModuleScript"):format(path, entry.className))
		end
	end
	for _, path in sortedKeys(folders) do
		if present[path] == nil then
			table.insert(problems, "missing from the model: folder " .. path)
		end
	end
	local known: { [string]: boolean } = {}
	for path in modules do
		known[path] = true
	end
	for path in folders do
		known[path] = true
	end
	for _, required in REQUIRED_DISTRIBUTION do
		local path, className = required[1], required[2]
		known[path] = true
		local entry = present[path]
		if entry == nil then
			table.insert(
				problems,
				("missing from the model: %s — the release metadata and the MIT text travel inside the package and are not optional"):format(
					path
				)
			)
		elseif entry.className ~= className then
			table.insert(problems, ("%s is a %s, expected %s"):format(path, entry.className, className))
		end
	end
	local paths = sortedKeys(present)
	for _, path in paths do
		if not known[path] then
			table.insert(problems, ("UNEXPECTED instance in the model: %s (%s)"):format(path, present[path].className))
		end
	end
	for _, path in paths do
		for _, segment in string.split(path, "/") do
			if FORBIDDEN_SEGMENTS[segment] and not (segment == "vendor" and approved[path]) then
				table.insert(problems, ("FORBIDDEN in the distribution: %s (segment '%s')"):format(path, segment))
			end
		end
		local lowered = string.lower(path)
		for _, needle in FORBIDDEN_SUBSTRINGS do
			if string.find(lowered, needle, 1, true) ~= nil then
				table.insert(problems, ("FORBIDDEN in the distribution: %s (contains '%s')"):format(path, needle))
			end
		end
	end
	local folderCount = 0
	for _ in folders do
		folderCount += 1
	end
	local moduleCount = 0
	for _ in modules do
		moduleCount += 1
	end
	return problems,
		{ modules = moduleCount, folders = folderCount, required = #REQUIRED_DISTRIBUTION, instances = #paths }
end

local function shown(env: Environment, path: string): string
	return Model.shown(env.root, path)
end

local function api(env: Environment, method: string, path: string, apiKey: string, body: string?, contentType: string?)
	return Assets.call(env.transport, method, path, apiKey, body, contentType)
end

local function gatherFacts(
	env: Environment,
	op: string,
	arguments: Arguments,
	config: Json.Object,
	apiKey: string?,
	useTransport: boolean
): Facts
	local version = Model.readVersion(env.root)
	local commit = git(env.root, { "rev-parse", "HEAD" })
	local sourceHash = Model.sourceHash(env.root)
	local recorded = Model.loadManifest(env.manifest)
	local fresh = env.build(false)
	local configAsset = Json.field(config, "assetId")
	local cloud: Cloud? = nil
	local moderation: unknown = nil
	if useTransport and apiKey ~= nil and truthy(configAsset) then
		local status, payload = api(env, "GET", "/v1/assets/" .. str(configAsset), apiKey)
		if status == 200 then
			cloud = {
				revisionId = Json.field(payload, "revisionId"),
				revisionCreateTime = Json.field(payload, "revisionCreateTime"),
			}
			moderation = Json.field(Json.field(payload, "moderationResult"), "moderationState")
		end
	end
	local creator = Json.field(config, "creator")
	local route = Json.field(config, "route")
	return {
		op = op,
		apiKeyPresent = apiKey ~= nil,
		gitDirty = porcelain(env.root) ~= "",
		argCommit = arguments.commit,
		headCommit = commit,
		argVersion = arguments.version,
		sourceVersion = version,
		sourceHash = sourceHash,
		freshBuildHash = fresh.bodyHash,
		manifestHash = Json.stringField(recorded, "bodyHash"),
		configCreator = { type = Json.field(creator, "type"), id = Json.field(creator, "id") },
		argCreatorType = arguments.creatorType,
		argCreatorId = arguments.creatorId,
		configAssetId = configAsset,
		argAssetId = arguments.assetId,
		configRoute = if truthy(route) then str(route) else "studio",
		argRoute = arguments.route,
		allowRouteOverride = arguments.allowRouteOverride,
		gate = readGateEvidence(env.gate),
		gatePath = shown(env, env.gate),
		latestReceipt = latestReceipt(env.receipts),
		cloudRevision = cloud,
		moderation = moderation,
		manifest = fresh,
	}
end

local function printVerdicts(say: (string) -> (), verdict: Verdict)
	say("")
	say("GUARDS")
	local codes: { [string]: boolean } = {}
	for _, refusal in verdict.refusals do
		codes[refusal.code] = true
	end
	for _, guard in GUARDS do
		local label, code = guard[1], guard[2]
		local mark = if codes[code] then "REFUSE" elseif verdict.evaluated[code] then "  ok  " else " n/a  "
		say(("  [%s] %s"):format(mark, label))
	end
	say("")
	if #verdict.refusals > 0 then
		say(("REFUSALS (%d)"):format(#verdict.refusals))
		for _, refusal in verdict.refusals do
			say(("  - %s: %s"):format(refusal.code, refusal.message))
		end
	else
		local count = 0
		for _ in verdict.evaluated do
			count += 1
		end
		say(("REFUSALS (0) — %d guard(s) evaluated, all passed"):format(count))
	end
end

local function describeRequest(env: Environment, method: string, path: string, request: Json.Object, file: string)
	local say = env.say
	say("")
	say("REQUEST THAT WOULD BE SENT")
	say(("  %s %s%s"):format(method, Assets.BASE, path))
	say(("  headers: %s, Accept: application/json"):format(REDACTED))
	say("  body: multipart/form-data")
	say(("    part 'request'     (application/json): %s"):format(Json.encode(request)))
	say(
		("    part 'fileContent' (%s): %s (%d bytes, sha256 %s) — contents not shown"):format(
			RBXM_CONTENT_TYPE,
			shown(env, file),
			Files.size(file),
			Hash.sha256(Files.read(file))
		)
	)
end

local function creationContext(config: Json.Object): Json.Object
	local creator = Json.field(config, "creator")
	local kind, id = Json.field(creator, "type"), Json.field(creator, "id")
	local inner = Json.object()
	if not truthy(kind) or not truthy(id) then
		Json.set(inner, "<userId or groupId>", "<unset — owner checkpoint>")
	else
		Json.set(inner, if kind == "user" then "userId" else "groupId", str(id))
	end
	return ordered({ { "creator", inner } })
end

type ReceiptInput = {
	operationPath: string?,
	assetRevision: Json.Object,
	moderation: unknown,
	actor: string,
	gate: Gate?,
}

local function writeReceipt(
	env: Environment,
	config: Json.Object,
	facts: Facts,
	input: ReceiptInput
): (string, Json.Object)
	local version = str(facts.sourceVersion)
	local commit = str(facts.headCommit)
	local gate = input.gate
	local operationId = lastSegment(input.operationPath or "")
	local receipt = ordered({
		{ "schema", RECEIPT_SCHEMA },
		{ "version", version },
		{ "sourceCommit", commit },
		{ "sourceHash", facts.sourceHash },
		{ "artifactSha256", if facts.manifest then facts.manifest.artifactSha256 else nil },
		{ "assetId", Json.field(config, "assetId") },
		{ "operationId", if operationId ~= "" then operationId else nil },
		{ "operationPath", input.operationPath },
		{ "assetRevision", input.assetRevision },
		{ "moderation", input.moderation },
		{ "publishedAt", nowIso() },
		{ "actor", input.actor },
		{ "route", Json.field(config, "route") },
		{ "toolchain", env.toolchain() },
		{
			"gateRun",
			ordered({
				{ "schema", if gate then gate.schema else nil },
				{ "tier", if gate then gate.tier else nil },
				{ "status", if gate then gate.status else nil },
				{ "commit", if gate then gate.commit else nil },
				{ "treeDirty", if gate then gate.treeDirty else nil },
				{ "sourceHash", if gate then gate.sourceHash else nil },
				{ "completedAt", if gate then gate.completedAt else nil },
				{ "runId", if gate then gate.runId else nil },
			}),
		},
		{
			"studio_verification",
			ordered({ { "status", "pending" }, { "by", nil }, { "date", nil }, { "notes", nil } }),
		},
	})
	Files.makeDirectory(env.receipts)
	local path = Files.join(env.receipts, ("%s-%s.json"):format(version, string.sub(commit, 1, 7)))
	Files.writeAtomic(path, Json.pretty(receipt))
	return path, receipt
end

local function recordVersion(env: Environment, config: Json.Object, receipt: Json.Object)
	local versions = Json.arrayField(config, "versions")
	if versions == nil then
		local fresh = Json.array()
		Json.set(config, "versions", fresh)
		versions = fresh
	end
	assert(versions ~= nil)
	table.insert(
		versions,
		ordered({
			{ "version", Json.field(receipt, "version") },
			{ "sourceCommit", Json.field(receipt, "sourceCommit") },
			{ "assetRevision", Json.field(Json.field(receipt, "assetRevision"), "revisionId") },
			{ "publishedAt", Json.field(receipt, "publishedAt") },
		})
	)
	saveConfig(env.config, config)
end

local function cmdStage(env: Environment, invocation: Cli.Invocation): number
	local quiet = Cli.switch(invocation, "quiet")
	local staged = Model.stage(env.root, Cli.flag(invocation, "out"), quiet)
	if not quiet then
		env.say("staged " .. shown(env, staged.path))
	end
	return 0
end

local function cmdManifest(env: Environment, invocation: Cli.Invocation): number
	local model, artifact, out =
		Cli.flag(invocation, "model"), Cli.flag(invocation, "artifact"), Cli.flag(invocation, "out")
	if model == nil or artifact == nil or out == nil then
		local missing: { string } = {}
		for _, name in { "model", "artifact", "out" } do
			if Cli.flag(invocation, name) == nil then
				table.insert(missing, "--" .. name)
			end
		end
		env.say("package manifest: the following arguments are required: " .. table.concat(missing, ", "))
		return 2
	end
	local manifest = Model.writeManifest(env.root, model, artifact, out)
	env.say(
		("manifest %s: %d instances (%d modules), body %s"):format(
			shown(env, out),
			manifest.instanceCount,
			manifest.moduleCount,
			string.sub(manifest.bodyHash, 1, 12)
		)
	)
	return 0
end

local function cmdBuild(env: Environment, invocation: Cli.Invocation): number
	local built, message =
		Model.build({ output = env.model, publisher = Cli.switch(invocation, "publisher"), root = env.root })
	env.say(message)
	if not built then
		return 2
	end
	local manifest = Model.loadManifest(env.manifest)
	if manifest == nil then
		env.say("package build: the builder produced no manifest")
		return 1
	end
	env.say(
		("  version %s  commit %s\n  sourceHash   %s\n  artifactSha  %s\n  manifest     %s instances, %s modules, body %s"):format(
			str(raw(manifest, "version")),
			str(raw(manifest, "sourceCommit")),
			str(raw(manifest, "sourceHash")),
			str(raw(manifest, "artifactSha256")),
			str(raw(manifest, "instanceCount")),
			str(raw(manifest, "moduleCount")),
			str(raw(manifest, "bodyHash"))
		)
	)
	return 0
end

local function cmdStatus(env: Environment): number
	local say = env.say
	local manifest = env.build(false)
	local config = loadConfig(env.config)
	local receipt = latestReceipt(env.receipts)
	local dirty = porcelain(env.root)
	say("package status")
	say("  route            " .. str(raw(config, "route")))
	say("  version          " .. manifest.version)
	say("  commit           " .. manifest.sourceCommit)
	say("  sourceHash       " .. manifest.sourceHash)
	say("  artifactSha256   " .. manifest.artifactSha256)
	local assetId = raw(config, "assetId")
	say("  assetId          " .. (if truthy(assetId) then str(assetId) else "(unset — owner checkpoint)"))
	say("  creator          " .. str(raw(config, "creator")))
	say("  working tree     " .. (if dirty ~= "" then "DIRTY" else "clean"))
	if dirty ~= "" then
		local lines = Files.lines(dirty)
		for index = 1, math.min(#lines, 10) do
			say("                   " .. stringext.trim(lines[index]))
		end
	end
	if receipt == nil then
		say("  last receipt     (none — nothing has ever been published)")
		say("  drift            n/a")
	else
		local drift = raw(receipt, "sourceHash") ~= manifest.sourceHash
		local commit = raw(receipt, "sourceCommit")
		say(
			("  last receipt     %s @ %s (%s)"):format(
				str(raw(receipt, "version")),
				if commit == nil then "" else prefix(commit, 7),
				str(raw(receipt, "publishedAt"))
			)
		)
		say("  drift            " .. (if drift then "YES — source has changed since the last publish" else "no"))
		local last, current = semver(raw(receipt, "version")), semver(manifest.version)
		if last ~= nil and current ~= nil then
			local order = compareVersions(current, last)
			if order > 0 then
				say(("  semver           advanced %s -> %s"):format(str(raw(receipt, "version")), manifest.version))
			elseif order == 0 then
				local same = raw(receipt, "sourceHash") == manifest.sourceHash
				say(
					("  semver           NOT advanced (still %s, %s)"):format(
						manifest.version,
						if same then "same source" else "DIFFERENT SOURCE — republishing this version is refused"
					)
				)
			else
				say(("  semver           BEHIND the last receipt (%s)"):format(str(raw(receipt, "version"))))
			end
		end
		local studio = Json.field(receipt, "studio_verification")
		local status = raw(studio, "status")
		say(
			"  studio check     "
				.. str(status)
				.. (
					if status == "verified"
						then (" by %s on %s"):format(str(raw(studio, "by")), str(raw(studio, "date")))
						else ""
				)
		)
	end
	local changelog = Files.join(env.root, "CHANGELOG.md")
	if Files.isFile(changelog) then
		local mentioned = string.find(Files.text(changelog), manifest.version, 1, true) ~= nil
		say(("  changelog        %s %s"):format(if mentioned then "mentions" else "DOES NOT mention", manifest.version))
	else
		say("  changelog        (CHANGELOG.md not present yet)")
	end
	local gate = readGateEvidence(env.gate)
	if gate == nil then
		local detail = if Files.isFile(env.gate)
			then "present but carries no readable Verify gate outcome"
			else "absent"
		say(("  gate evidence    %s (%s)"):format(detail, shown(env, env.gate)))
	else
		local agrees = gate.schema == GATE_SCHEMA
			and gate.tier == "release"
			and gate.status == "PASS"
			and gate.treeDirty == false
			and gate.commit == git(env.root, { "rev-parse", "HEAD" })
			and gate.sourceHash == manifest.sourceHash
		say(
			("  gate evidence    %s/%s at %s, %s"):format(
				str(gate.tier),
				str(gate.status),
				prefix(gate.commit, 7),
				if agrees then "attests this tree" else "DOES NOT attest this tree"
			)
		)
	end
	return 0
end

local function indented(say: (string) -> (), text: string)
	local stripped = stringext.trim(text)
	if stripped == "" then
		return
	end
	for _, line in Files.lines(stripped) do
		say("         " .. line)
	end
end

local function cmdVerify(env: Environment, invocation: Cli.Invocation): number
	local say = env.say
	say("package verify")
	local failures: { string } = {}
	local manifest = env.build(false)
	say(("  [ ok ] build: %d instances, %d modules"):format(manifest.instanceCount, manifest.moduleCount))

	local problems, counts = inspectTree(env.root, manifest)
	if #problems > 0 then
		table.insert(failures, "tree inspection")
		say(("  [FAIL] tree inspection: %d problem(s)"):format(#problems))
		for _, problem in problems do
			say("         - " .. problem)
		end
	else
		say(
			("  [ ok ] tree inspection: %d modules, %d folders and the %d-instance Distribution subtree present, nothing else"):format(
				counts.modules,
				counts.folders,
				counts.required
			)
		)
	end

	local work = Files.temporaryDirectory("facet-stage-")
	local staged = Model.stage(env.root, work, true)
	Files.remove(work)
	if #staged.placeholders > 0 then
		say("  [warn] distribution notices: placeholder text for " .. table.concat(staged.placeholders, ", "))
	else
		say("  [ ok ] distribution notices: LICENSE and THIRD_PARTY_NOTICES copied from the root files")
	end

	local findings = purity.check(Rule.context(env.root))
	if #findings == 0 then
		say("  [ ok ] library purity")
	else
		table.insert(failures, "library purity")
		say("  [FAIL] library purity")
		say(("         %s: %d problem(s)"):format(purity.name, #findings))
		for _, finding in findings do
			say("           - " .. finding)
		end
	end

	if Cli.switch(invocation, "skip-canary") then
		say("  [skip] packaged-consumer canary (--skip-canary)")
	else
		local canary = Run.capture({ Run.lute(), "run", CANARY }, { cwd = env.root })
		indented(say, canary.stdout .. canary.stderr)
		if canary.ok then
			say("  [ ok ] packaged-consumer canary")
		else
			table.insert(failures, "packaged-consumer canary")
			say("  [FAIL] packaged-consumer canary")
		end
	end

	say("")
	if #failures > 0 then
		say(("package verify: FAIL (%s)"):format(table.concat(failures, ", ")))
		return 1
	end
	say("package verify: PASS")
	return 0
end

type Preamble = {
	config: Json.Object,
	route: string,
	apiKey: string?,
	facts: Facts,
	verdict: Verdict,
}

local function preamble(env: Environment, op: string, arguments: Arguments): Preamble
	local config = loadConfig(env.config)
	local configured = raw(config, "route")
	local route = arguments.route or (if truthy(configured) then str(configured) else "studio")
	if route ~= "studio" and route ~= "open-cloud" then
		env.say(("package %s: unknown route %s (expected 'studio' or 'open-cloud')"):format(op, repr(route)))
		stop(1)
	end
	local apiKey = env.apiKey()
	local facts = gatherFacts(env, op, arguments, config, apiKey, apiKey ~= nil)
	local verdict = env.decide(facts)
	env.say(("package %s (route %s, %s)"):format(op, route, if arguments.confirm then "CONFIRMED" else "DRY RUN"))
	env.say(
		("  version %s  commit %s  sourceHash %s"):format(
			str(facts.sourceVersion),
			prefix(facts.headCommit, 7),
			prefix(facts.sourceHash, 12)
		)
	)
	return { config = config, route = route, apiKey = apiKey, facts = facts, verdict = verdict }
end

local function studioPublisherSteps(env: Environment, config: Json.Object, verb: string)
	local say = env.say
	env.build(true)
	say("")
	say("STUDIO ROUTE — do these steps by hand, then come back")
	say(("  1. Open %s in Roblox Studio."):format(shown(env, env.publisher)))
	say("  2. In Explorer, select ReplicatedStorage > Facet.")
	if verb == "create" then
		say("  3. Right-click it and choose 'Convert to Package'.")
		say("     Name:        " .. str(raw(config, "displayName")))
		say("     Description: " .. str(raw(config, "description")))
		say("     Ownership:   the account named in package/facet-package.json's creator.")
		say("                  Ownership transfers are NOT supported by the asset system — choose once.")
		say("  4. Copy the asset id from the new PackageLink's PackageId.")
		say("  5. Re-run: lute run tools/facet package create --confirm --version <v> --commit <sha> --asset-id <id>")
	else
		say("  3. Right-click it and choose 'Publish to Package'.")
		say("  4. Add a version description naming the version and commit above.")
		say("  5. Leave this command running; it polls the asset's version list for the new version.")
	end
end

local function dryRunOrRefuse(env: Environment, arguments: Arguments, verdict: Verdict): number?
	if not arguments.confirm then
		env.say("")
		env.say("DRY RUN — no network call was made. Re-run with --confirm once every guard is green.")
		return 0
	end
	if #verdict.refusals > 0 then
		env.say("")
		env.say(("REFUSED — %d guard(s) failed; nothing was sent."):format(#verdict.refusals))
		return 1
	end
	return nil
end

local function excerpt(payload: unknown, length: number): string
	return string.sub(Json.encode(payload), 1, length)
end

local function modelPart(env: Environment, request: Json.Object): (string, string)
	return Assets.form({
		{ name = "request", value = Json.encode(request) },
		{
			name = "fileContent",
			value = Files.read(env.model),
			filename = Files.name(env.model),
			contentType = RBXM_CONTENT_TYPE,
		},
	})
end

local function operationResult(
	env: Environment,
	apiKey: string,
	status: number,
	payload: Json.Object,
	verb: string
): (Json.Object?, string?)
	if status ~= 200 then
		env.say(("  %s failed: HTTP %d %s"):format(verb, status, excerpt(payload, 300)))
		return nil, nil
	end
	local operationPath = raw(payload, "path")
	local polledStatus, polled = Assets.poll(env.transport, str(operationPath), apiKey, env.clock, env.say)
	if polledStatus ~= 200 or not truthy(raw(polled, "done")) or truthy(raw(polled, "error")) then
		env.say(("  operation did not complete: HTTP %d %s"):format(polledStatus, excerpt(polled, 300)))
		return nil, nil
	end
	return Json.objectField(polled, "response") or Json.object(),
		if type(operationPath) == "string" then operationPath else nil
end

local function integer(value: unknown): number?
	local number = if type(value) == "number"
		then value
		elseif type(value) == "string" then tonumber(stringext.trim(value))
		else nil
	if number == nil or number ~= math.floor(number) then
		return nil
	end
	return number
end

local function cmdCreate(env: Environment, arguments: Arguments): number
	local say = env.say
	local opened = preamble(env, "create", arguments)
	local config, route, apiKey, facts = opened.config, opened.route, opened.apiKey, opened.facts
	printVerdicts(say, opened.verdict)
	local request = ordered({
		{ "assetType", ASSET_TYPE },
		{ "displayName", Json.field(config, "displayName") },
		{ "description", Json.field(config, "description") },
		{ "creationContext", creationContext(config) },
	})
	if route == "open-cloud" then
		describeRequest(env, "POST", "/v1/assets", request, env.model)
	else
		say("")
		say("REQUEST THAT WOULD BE SENT")
		say("  none on create — the studio route mints the asset in Studio and this command only READS it back:")
		say(("  GET %s/v1/assets/<the id you supply with --asset-id>"):format(Assets.BASE))
		say("  headers: " .. REDACTED)
	end
	local early = dryRunOrRefuse(env, arguments, opened.verdict)
	if early ~= nil then
		return early
	end
	local key = assert(apiKey, "the api-key guard passed without a key")

	if route == "studio" then
		local assetId = arguments.assetId
		if not truthy(assetId) or assetId == nil then
			studioPublisherSteps(env, config, "create")
			say("")
			say("No --asset-id given, so nothing was recorded. Do the steps above and re-run with --asset-id.")
			return 0
		end
		local status, payload = api(env, "GET", "/v1/assets/" .. assetId, key)
		if status ~= 200 then
			say(("  read-back failed: HTTP %d %s"):format(status, excerpt(payload, 300)))
			return 1
		end
		local creator = Json.field(Json.field(payload, "creationContext"), "creator")
		if not truthy(creator) then
			creator = Json.object()
		end
		local configured = Json.field(config, "creator")
		if not truthy(configured) then
			configured = Json.object()
		end
		local field = if Json.field(configured, "type") == "user" then "userId" else "groupId"
		if str(Json.field(creator, field)) ~= str(Json.field(configured, "id")) then
			say(
				("  read-back refuses the id: asset %s belongs to %s, not %s"):format(
					assetId,
					repr(creator),
					repr(configured)
				)
			)
			return 1
		end
		local assetType = raw(payload, "assetType")
		if
			truthy(assetType)
			and string.find(string.lower(str(assetType)), string.lower(ASSET_TYPE), 1, true) == nil
		then
			say(("  read-back refuses the id: asset %s is a %s, not a Model"):format(assetId, str(assetType)))
			return 1
		end
		local number = integer(assetId)
		if number == nil then
			stop(1, ("package create: --asset-id %s is not an integer"):format(assetId))
		end
		Json.set(config, "assetId", number)
		saveConfig(env.config, config)
		say(("  recorded assetId %s in %s"):format(assetId, shown(env, env.config)))
		return 0
	end

	local body, contentType = modelPart(env, request)
	local status, payload = api(env, "POST", "/v1/assets", key, body, contentType)
	local asset, operationPath = operationResult(env, key, status, payload, "create")
	if asset == nil then
		return 1
	end
	local created = integer(raw(asset, "assetId"))
	if created == nil then
		stop(
			1,
			("package create: the operation returned asset id %s, not an integer"):format(str(raw(asset, "assetId")))
		)
	end
	Json.set(config, "assetId", created)
	saveConfig(env.config, config)
	say(("  created assetId %s (revision %s)"):format(str(created), str(raw(asset, "revisionId"))))
	local path, receipt = writeReceipt(env, config, facts, {
		operationPath = operationPath,
		assetRevision = ordered({
			{ "revisionId", Json.field(asset, "revisionId") },
			{ "revisionCreateTime", Json.field(asset, "revisionCreateTime") },
		}),
		moderation = Json.field(Json.field(asset, "moderationResult"), "moderationState"),
		actor = arguments.actor or "maintainer",
		gate = facts.gate,
	})
	recordVersion(env, config, receipt)
	say("  receipt " .. shown(env, path))
	return 0
end

local function versionsOf(payload: Json.Object): Json.Array
	local assetVersions = raw(payload, "assetVersions")
	if truthy(assetVersions) then
		return Json.asArray(assetVersions) or Json.array()
	end
	local data = raw(payload, "data")
	if truthy(data) then
		return Json.asArray(data) or Json.array()
	end
	return Json.array()
end

local function versionNumber(version: unknown): string
	local path = raw(version, "path")
	return lastSegment(if path == nil then "" else str(path))
end

local function cmdPublish(env: Environment, arguments: Arguments): number
	local say = env.say
	local opened = preamble(env, "publish", arguments)
	local config, route, apiKey, facts = opened.config, opened.route, opened.apiKey, opened.facts
	printVerdicts(say, opened.verdict)
	local configured = raw(config, "assetId")
	local assetId = if truthy(configured) then str(configured) else UNSET_ASSET
	local request = ordered({
		{ "assetId", assetId },
		{ "assetType", ASSET_TYPE },
		{ "displayName", Json.field(config, "displayName") },
		{ "description", Json.field(config, "description") },
	})
	if route == "open-cloud" then
		describeRequest(env, "PATCH", "/v1/assets/" .. assetId, request, env.model)
		say("  NOTE: the usage guide says content updates currently work for .fbx only. This route is")
		say("        implemented; verify .rbxm package behavior in Studio before release.")
	else
		say("")
		say("REQUEST THAT WOULD BE SENT")
		say("  none on publish — the studio route publishes in Studio and this command only READS:")
		say(("  GET %s/v1/assets/%s/versions?maxPageSize=1"):format(Assets.BASE, assetId))
		say("  headers: " .. REDACTED)
	end
	local early = dryRunOrRefuse(env, arguments, opened.verdict)
	if early ~= nil then
		return early
	end
	local key = assert(apiKey, "the api-key guard passed without a key")
	local versionsPath = ("/v1/assets/%s/versions?maxPageSize=1"):format(assetId)

	if route == "studio" then
		local baseline: string? = arguments.baselineRevision
		local source = "--baseline-revision"
		if baseline == nil then
			local status, payload = api(env, "GET", versionsPath, key)
			if status ~= 200 then
				say(("  cannot read the asset's version list: HTTP %d %s"):format(status, excerpt(payload, 200)))
				say("  REFUSED: without a pre-publish baseline this command cannot tell a version the human just")
				say("           published from the one that was already there. Re-run with --baseline-revision")
				say("           <n>, the newest version number you can see on the asset today.")
				return 1
			end
			local versions = versionsOf(payload)
			if #versions > 0 then
				baseline = versionNumber(versions[1])
				source = "read from the cloud before publishing"
			else
				source = "the asset has no versions yet, so any version is new"
			end
		end
		say("")
		say(("  pre-publish baseline: %s (%s)"):format(baseline or "(none)", source))
		studioPublisherSteps(env, config, "publish")
		say("")
		say(
			("  polling %s/v1/assets/%s/versions for a version other than %s"):format(
				Assets.BASE,
				assetId,
				repr(baseline)
			)
		)
		local deadline = env.clock.now() + arguments.timeout
		local found: unknown = nil
		while env.clock.now() < deadline do
			local status, payload = api(env, "GET", versionsPath, key)
			if status == 200 then
				local versions = versionsOf(payload)
				if #versions > 0 then
					local newest = versions[1]
					local number = versionNumber(newest)
					if baseline == nil or number ~= baseline then
						found = newest
						break
					end
				end
			end
			env.clock.sleep(math.min(arguments.poll, 60))
		end
		if found == nil then
			say(
				("  no version other than %s appeared within %ds; nothing was recorded"):format(
					repr(baseline),
					arguments.timeout
				)
			)
			return 1
		end
		local number = versionNumber(found)
		local moderation = Json.field(Json.field(found, "moderationResult"), "moderationState")
		say(("  observed version %s (moderation %s)"):format(number, str(moderation)))
		local path, receipt = writeReceipt(env, config, facts, {
			operationPath = nil,
			assetRevision = ordered({ { "revisionId", number }, { "revisionPath", Json.field(found, "path") } }),
			moderation = moderation,
			actor = arguments.actor or "maintainer",
			gate = facts.gate,
		})
		recordVersion(env, config, receipt)
		say("  receipt " .. shown(env, path))
		return 0
	end

	local body, contentType = modelPart(env, request)
	local status, payload = api(env, "PATCH", "/v1/assets/" .. assetId, key, body, contentType)
	local asset, operationPath = operationResult(env, key, status, payload, "publish")
	if asset == nil then
		return 1
	end
	local moderation = Json.field(Json.field(asset, "moderationResult"), "moderationState")
	say(("  published revision %s (moderation %s)"):format(str(raw(asset, "revisionId")), str(moderation)))
	if moderation ~= nil and (type(moderation) ~= "string" or not APPROVED_MODERATION[moderation]) then
		say(
			("  WARNING: moderation is %s; the receipt records it and `status` will keep saying so"):format(
				repr(moderation)
			)
		)
	end
	local path, receipt = writeReceipt(env, config, facts, {
		operationPath = operationPath,
		assetRevision = ordered({
			{ "revisionId", Json.field(asset, "revisionId") },
			{ "revisionCreateTime", Json.field(asset, "revisionCreateTime") },
		}),
		moderation = moderation,
		actor = arguments.actor or "maintainer",
		gate = facts.gate,
	})
	recordVersion(env, config, receipt)
	say("  receipt " .. shown(env, path))
	return 0
end

local function cmdRollback(env: Environment): number
	local say = env.say
	local config = loadConfig(env.config)
	local configured = raw(config, "assetId")
	local assetId = if truthy(configured) then str(configured) else UNSET_ASSET
	local receipt = latestReceipt(env.receipts)
	say("package rollback — this command never uploads anything.")
	say("")
	say("ROUTE A — Studio package version history (the documented Package mechanism)")
	say("  1. In Studio, right-click the package > Package Options > Package Details.")
	say("  2. Open the Versions tab: every published version with its date and description.")
	say("  3. Click the checkmark beside the version to restore, then Submit.")
	say("  4. Note: restoring does NOT reset package attributes; revert those separately.")
	say("  5. Consumers on AutoUpdate pick the restored version up on next place-open;")
	say("     a locally modified copy has AutoUpdate disabled and is skipped, not overwritten.")
	say("")
	say("ROUTE B — Open Cloud asset-version rollback (the scripted mechanism)")
	say(("  POST %s/v1/assets/%s/versions:rollback"):format(Assets.BASE, assetId))
	say("  headers: " .. REDACTED)
	say("  body: multipart/form-data")
	say(("    part 'assetVersion': assets/%s/versions/<versionNumber>"):format(assetId))
	say("  Scopes: asset:read AND asset:write. Rate limit 100/min.")
	say(("  List the versions first: GET %s/v1/assets/%s/versions?maxPageSize=50"):format(Assets.BASE, assetId))
	say("")
	say("WHICH ONE. The two sequences are not proved to be the same sequence — the docs")
	say("do not establish equivalent Package versions and Asset revisions.")
	say("Roll back on the route that published the version.")
	if receipt ~= nil then
		say("")
		say(
			("  newest receipt: %s route %s revision %s"):format(
				str(raw(receipt, "version")),
				str(raw(receipt, "route")),
				str(Json.field(Json.field(receipt, "assetRevision"), "revisionId"))
			)
		)
	end
	return 0
end

local function cmdStamp(env: Environment, invocation: Cli.Invocation): number
	local path = Cli.flag(invocation, "receipt")
	if path == nil then
		env.say("package stamp: the following arguments are required: --receipt")
		return 2
	end
	local receipt = loadConfig(path)
	if not Cli.switch(invocation, "studio-verified") then
		env.say("package stamp: pass --studio-verified to record a completed Studio check")
		return 1
	end
	local by = Cli.flag(invocation, "by")
	Json.set(
		receipt,
		"studio_verification",
		ordered({
			{ "status", "verified" },
			{ "by", by },
			{ "date", nowIso() },
			{ "notes", Cli.flag(invocation, "notes") },
		})
	)
	Files.write(path, Json.pretty(receipt))
	env.say(("stamped %s: verified by %s"):format(shown(env, path), str(by)))
	return 0
end

local function realBuild(root: string, model: string, xml: string, manifest: string): (boolean) -> Model.Manifest
	return function(publisher: boolean): Model.Manifest
		local built, message = Model.build({ output = model, publisher = publisher, root = root })
		if not built then
			print(message)
			stop(2)
		end
		return Model.writeManifest(root, xml, model, manifest)
	end
end

local function environment(invocation: Cli.Invocation): Environment
	local root = "."
	local model = Files.join(root, Model.DEFAULT_OUTPUT)
	local base = string.sub(model, 1, -6)
	local xml = base .. ".rbxmx"
	local manifest = base .. ".manifest.json"
	return {
		root = root,
		config = Cli.flag(invocation, "config") or DEFAULT_CONFIG,
		receipts = Cli.flag(invocation, "receipts") or DEFAULT_RECEIPTS,
		gate = GATE_EVIDENCE,
		model = model,
		xml = xml,
		manifest = manifest,
		publisher = Files.join(root, Model.PUBLISHER_PLACE),
		transport = Assets.network,
		decide = decide,
		apiKey = function(): string?
			local key = Run.env("ROBLOX_API_KEY")
			if key == nil or stringext.trim(key) == "" then
				return nil
			end
			return stringext.trim(key)
		end,
		build = realBuild(root, model, xml, manifest),
		toolchain = toolchain,
		clock = Assets.realClock(),
		say = function(line: string)
			print(line)
		end,
	}
end

local RELEASE_VALUES: { string } = {
	"route",
	"version",
	"commit",
	"asset-id",
	"creator-id",
	"creator-type",
	"actor",
	"baseline-revision",
	"timeout",
	"poll",
}
local RELEASE_SWITCHES: { string } = { "confirm", "allow-route-override" }

local VALUES: { string } = { "config", "receipts", "out", "model", "artifact", "receipt", "by", "notes" }
for _, name in RELEASE_VALUES do
	table.insert(VALUES, name)
end

local KNOWN: { [string]: { string } } = {
	stage = { "out", "quiet" },
	manifest = { "model", "artifact", "out" },
	build = { "publisher", "verify" },
	status = {},
	verify = { "skip-canary" },
	create = {},
	publish = {},
	rollback = {},
	stamp = { "receipt", "studio-verified", "by", "notes" },
	["source-hash"] = {},
}
for _, name in RELEASE_VALUES do
	table.insert(KNOWN.create, name)
	table.insert(KNOWN.publish, name)
end
for _, name in RELEASE_SWITCHES do
	table.insert(KNOWN.create, name)
	table.insert(KNOWN.publish, name)
end

local function usageError(message: string): number
	print("package: " .. message)
	print("")
	print(USAGE)
	return 2
end

local function releaseArguments(invocation: Cli.Invocation): (Arguments?, string?)
	local route: string? = Cli.flag(invocation, "route")
	if route ~= nil and route ~= "studio" and route ~= "open-cloud" then
		return nil, ("argument --route: invalid choice: %s (choose from 'studio', 'open-cloud')"):format(repr(route))
	end
	local creatorType: string? = Cli.flag(invocation, "creator-type")
	if creatorType ~= nil and creatorType ~= "user" and creatorType ~= "group" then
		return nil,
			("argument --creator-type: invalid choice: %s (choose from 'user', 'group')"):format(repr(creatorType))
	end
	local numbers: { [string]: number } = { timeout = 1800, poll = 15 }
	for name in numbers do
		local text = Cli.flag(invocation, name)
		if text ~= nil then
			local value = integer(text)
			if value == nil then
				return nil, ("argument --%s: invalid int value: %s"):format(name, repr(text))
			end
			numbers[name] = value
		end
	end
	return {
		confirm = Cli.switch(invocation, "confirm"),
		route = Cli.flag(invocation, "route"),
		allowRouteOverride = Cli.switch(invocation, "allow-route-override"),
		version = Cli.flag(invocation, "version"),
		commit = Cli.flag(invocation, "commit"),
		assetId = Cli.flag(invocation, "asset-id"),
		creatorId = Cli.flag(invocation, "creator-id"),
		creatorType = Cli.flag(invocation, "creator-type"),
		actor = Cli.flag(invocation, "actor"),
		baselineRevision = Cli.flag(invocation, "baseline-revision"),
		timeout = numbers.timeout,
		poll = numbers.poll,
	},
		nil
end

local register: (Verify.Harness, string) -> ()

local function run(invocation: Cli.Invocation): number
	if Cli.switch(invocation, "selftest") then
		return Gate.selftest("tools/commands", "tools/commands::package::")
	end
	local subcommand = invocation.positional[1]
	if subcommand == nil then
		print(USAGE)
		return 2
	end
	local known = KNOWN[subcommand]
	if known == nil then
		return usageError(("invalid command '%s'"):format(subcommand))
	end
	if #invocation.positional > 1 then
		return usageError("unrecognized arguments: " .. table.concat(invocation.positional, " ", 2))
	end
	local allowed = table.clone(known)
	table.insert(allowed, "config")
	table.insert(allowed, "receipts")
	local unknown = Cli.unknownFlags(invocation, allowed)
	if unknown ~= nil or invocation.flags.json ~= nil then
		return usageError("unrecognized arguments: " .. (unknown or "--json"))
	end
	for _, name in VALUES do
		if invocation.flags[name] == true then
			return usageError(("argument --%s: expected one argument"):format(name))
		end
	end
	if subcommand == "source-hash" then
		print(Model.sourceHash("."))
		return 0
	end
	local checked, message = Snapshot.check(".", "compose")
	print(message)
	if not checked then
		return 1
	end
	local env = environment(invocation)
	return guarded(env.say, function(): number
		if subcommand == "stage" then
			return cmdStage(env, invocation)
		elseif subcommand == "manifest" then
			return cmdManifest(env, invocation)
		elseif subcommand == "build" then
			local code = cmdBuild(env, invocation)
			if code == 0 and Cli.switch(invocation, "verify") then
				return cmdVerify(env, invocation)
			end
			return code
		elseif subcommand == "status" then
			return cmdStatus(env)
		elseif subcommand == "verify" then
			return cmdVerify(env, invocation)
		elseif subcommand == "rollback" then
			return cmdRollback(env)
		elseif subcommand == "stamp" then
			return cmdStamp(env, invocation)
		end
		local arguments, problem = releaseArguments(invocation)
		if arguments == nil then
			return usageError(problem or "invalid arguments")
		end
		if subcommand == "create" then
			return cmdCreate(env, arguments)
		end
		return cmdPublish(env, arguments)
	end)
end

local GOOD_COMMIT = string.rep("c", 40)
local GOOD_SOURCE_HASH = string.rep("s", 64)
local SELFTEST_KEY = "selftest-key-never-sent"

local function receiptOf(version: string, sourceHash: string, operationPath: string, revision: string?): Json.Object
	return ordered({
		{ "version", version },
		{ "sourceHash", sourceHash },
		{ "operationPath", operationPath },
		{ "assetRevision", if revision then ordered({ { "revisionId", revision } }) else nil },
	})
end

local function goodGate(): Gate
	return {
		schema = GATE_SCHEMA,
		tier = "release",
		status = "PASS",
		commit = GOOD_COMMIT,
		treeDirty = false,
		sourceHash = GOOD_SOURCE_HASH,
		completedAt = "2026-08-30T00:00:00Z",
	}
end

local function goodFacts(op: string): Facts
	local facts: Facts = {
		op = op,
		apiKeyPresent = true,
		gitDirty = false,
		argCommit = GOOD_COMMIT,
		headCommit = GOOD_COMMIT,
		argVersion = "0.11.0",
		sourceVersion = "0.11.0",
		sourceHash = GOOD_SOURCE_HASH,
		freshBuildHash = string.rep("b", 64),
		manifestHash = string.rep("b", 64),
		configCreator = { type = "user", id = 1234 },
		argCreatorType = "user",
		argCreatorId = 1234,
		configAssetId = nil,
		argAssetId = nil,
		configRoute = "studio",
		argRoute = nil,
		allowRouteOverride = false,
		gate = goodGate(),
		gatePath = GATE_EVIDENCE,
		latestReceipt = nil,
		cloudRevision = nil,
		moderation = nil,
	}
	if op == "publish" then
		facts.configAssetId = 999
		facts.argAssetId = 999
		facts.latestReceipt = receiptOf("0.10.0", "old" .. string.rep("0", 61), "operations/op-1", "3")
		facts.cloudRevision = { revisionId = "3", revisionCreateTime = nil }
		facts.moderation = "Approved"
	end
	return facts
end

type RefusalCase = { code: string, op: string, label: string, change: (Facts) -> () }

local function gateWith(change: (Gate) -> ()): Gate
	local gate = goodGate()
	change(gate)
	return gate
end

local REFUSAL_CASES: { RefusalCase } = {
	{
		code = "api-key-missing",
		op = "create",
		label = "no API key",
		change = function(facts: Facts)
			facts.apiKeyPresent = false
		end,
	},
	{
		code = "dirty-tree",
		op = "create",
		label = "a dirty tree",
		change = function(facts: Facts)
			facts.gitDirty = true
		end,
	},
	{
		code = "commit-mismatch",
		op = "create",
		label = "no --commit",
		change = function(facts: Facts)
			facts.argCommit = nil
		end,
	},
	{
		code = "commit-mismatch",
		op = "create",
		label = "a --commit that is not HEAD",
		change = function(facts: Facts)
			facts.argCommit = string.rep("d", 40)
		end,
	},
	{
		code = "version-mismatch",
		op = "create",
		label = "no --version",
		change = function(facts: Facts)
			facts.argVersion = nil
		end,
	},
	{
		code = "version-mismatch",
		op = "create",
		label = "a --version that is not Facet.VERSION",
		change = function(facts: Facts)
			facts.argVersion = "9.9.9"
		end,
	},
	{
		code = "build-drift",
		op = "create",
		label = "a fresh build that differs from the manifest",
		change = function(facts: Facts)
			facts.freshBuildHash = string.rep("x", 64)
		end,
	},
	{
		code = "build-drift",
		op = "create",
		label = "no recorded manifest",
		change = function(facts: Facts)
			facts.manifestHash = nil
		end,
	},
	{
		code = "creator-unset",
		op = "create",
		label = "no configured creator",
		change = function(facts: Facts)
			facts.configCreator = { type = nil, id = nil }
			facts.argCreatorType = nil
			facts.argCreatorId = nil
		end,
	},
	{
		code = "creator-mismatch",
		op = "create",
		label = "another --creator-id",
		change = function(facts: Facts)
			facts.argCreatorId = 4321
		end,
	},
	{
		code = "creator-mismatch",
		op = "create",
		label = "another --creator-type",
		change = function(facts: Facts)
			facts.argCreatorType = "group"
		end,
	},
	{
		code = "asset-id-present",
		op = "create",
		label = "an asset id already recorded",
		change = function(facts: Facts)
			facts.configAssetId = 777
		end,
	},
	{
		code = "asset-id-missing",
		op = "publish",
		label = "no recorded asset id",
		change = function(facts: Facts)
			facts.configAssetId = nil
			facts.argAssetId = nil
			facts.cloudRevision = nil
		end,
	},
	{
		code = "asset-id-mismatch",
		op = "publish",
		label = "another --asset-id",
		change = function(facts: Facts)
			facts.argAssetId = 555
		end,
	},
	{
		code = "route-override",
		op = "create",
		label = "an unacknowledged --route",
		change = function(facts: Facts)
			facts.argRoute = "open-cloud"
		end,
	},
	{
		code = "gate-evidence-missing",
		op = "create",
		label = "no gate evidence",
		change = function(facts: Facts)
			facts.gate = nil
		end,
	},
	{
		code = "gate-evidence-schema",
		op = "create",
		label = "another evidence schema",
		change = function(facts: Facts)
			facts.gate = gateWith(function(gate: Gate)
				gate.schema = "some-other-schema/9"
			end)
		end,
	},
	{
		code = "gate-evidence-tier",
		op = "create",
		label = "a fast-tier run",
		change = function(facts: Facts)
			facts.gate = gateWith(function(gate: Gate)
				gate.tier = "fast"
			end)
		end,
	},
	{
		code = "gate-evidence-failed",
		op = "create",
		label = "a failed run",
		change = function(facts: Facts)
			facts.gate = gateWith(function(gate: Gate)
				gate.status = "FAIL"
			end)
		end,
	},
	{
		code = "gate-evidence-dirty",
		op = "create",
		label = "a run on a dirty tree",
		change = function(facts: Facts)
			facts.gate = gateWith(function(gate: Gate)
				gate.treeDirty = true
			end)
		end,
	},
	{
		code = "gate-evidence-commit",
		op = "create",
		label = "evidence for another commit",
		change = function(facts: Facts)
			facts.gate = gateWith(function(gate: Gate)
				gate.commit = string.rep("d", 40)
			end)
		end,
	},
	{
		code = "gate-evidence-source",
		op = "create",
		label = "evidence for another source",
		change = function(facts: Facts)
			facts.gate = gateWith(function(gate: Gate)
				gate.sourceHash = string.rep("x", 64)
			end)
		end,
	},
	{
		code = "operation-in-flight",
		op = "publish",
		label = "an unresolved operation",
		change = function(facts: Facts)
			facts.latestReceipt = receiptOf("0.10.0", "old" .. string.rep("0", 61), "operations/stuck", nil)
			facts.cloudRevision = nil
		end,
	},
	{
		code = "cloud-revision-newer",
		op = "publish",
		label = "a newer cloud revision",
		change = function(facts: Facts)
			facts.cloudRevision = { revisionId = "4", revisionCreateTime = nil }
		end,
	},
	{
		code = "version-not-advanced",
		op = "publish",
		label = "the same version and source",
		change = function(facts: Facts)
			facts.latestReceipt = receiptOf("0.11.0", string.rep("s", 64), "operations/op-1", "3")
		end,
	},
	{
		code = "version-hash-conflict",
		op = "publish",
		label = "the same version from another source",
		change = function(facts: Facts)
			facts.latestReceipt = receiptOf("0.11.0", "different" .. string.rep("0", 55), "operations/op-1", "3")
		end,
	},
	{
		code = "moderation-not-approved",
		op = "publish",
		label = "a rejected asset",
		change = function(facts: Facts)
			facts.moderation = "Rejected"
		end,
	},
}

local function codesOf(verdict: Verdict): { string }
	local codes: { string } = {}
	for _, refusal in verdict.refusals do
		table.insert(codes, refusal.code)
	end
	return codes
end

type Real = { version: string, commit: string, sourceHash: string }

local realFacts: Real? = nil

local function real(): Real
	local known = realFacts
	if known ~= nil then
		return known
	end
	local commit = Model.headCommit(".")
	if commit == nil then
		error("the selftest needs a git checkout: git rev-parse HEAD failed", 0)
	end
	local fresh: Real = { version = Model.readVersion("."), commit = commit, sourceHash = Model.sourceHash(".") }
	realFacts = fresh
	return fresh
end

local function gateBuild(clean: boolean): Json.Object
	local facts = real()
	return ordered({
		{ "commit", facts.commit },
		{ "tree", string.rep("t", 40) },
		{ "clean", clean },
		{ "digest", facts.sourceHash },
	})
end

local function gateAcceptance(verdict: string, releasable: boolean, complete: boolean): Json.Object
	return ordered({ { "verdict", verdict }, { "releasable", releasable }, { "complete", complete } })
end

local function gateDocument(overrides: { { unknown } }?): Json.Object
	local document = ordered({
		{ "schemaVersion", 1 },
		{ "gate", GATE_ID },
		{ "runId", "selftest-run" },
		{ "build", gateBuild(true) },
		{ "acceptance", gateAcceptance("release", true, true) },
	})
	if overrides ~= nil then
		for _, entry in overrides do
			local key = entry[1]
			if type(key) == "string" then
				Json.set(document, key, entry[2])
			end
		end
	end
	return document
end

local SYNTHETIC_MODEL = table.concat({
	'<roblox version="4">',
	'  <Item class="ModuleScript" referent="RBX0">',
	"    <Properties>",
	'      <string name="Name">Facet</string>',
	'      <string name="Source"><![CDATA[return {}]]></string>',
	"    </Properties>",
	"  </Item>",
	"</roblox>",
	"",
}, "\n")

local CREATED_ASSET = {
	path = "assets/424242",
	assetId = "424242",
	revisionId = "1",
	revisionCreateTime = "2026-08-30T00:00:00Z",
	assetType = "ASSET_TYPE_MODEL",
	creationContext = { creator = { userId = "1234" } },
	moderationResult = { moderationState = "MODERATION_STATE_APPROVED" },
}

type Work = {
	directory: string,
	env: Environment,
	output: { string },
	fake: Assets.Fake,
}

local function noRefusals(_facts: Facts): Verdict
	return { refusals = {}, evaluated = {} }
end

local function workspace(test: Verify.Context, script: { Assets.Canned }, decider: Decide): Work
	local directory = Files.temporaryDirectory("facet-package-selftest-")
	test:defer(function()
		Files.remove(directory)
	end)
	local output: { string } = {}
	local fake = Assets.fake(script)
	local model = Files.join(directory, "Facet.rbxm")
	local xml = Files.join(directory, "Facet.rbxmx")
	local manifest = Files.join(directory, "Facet.manifest.json")
	Files.write(model, "<roblox!\0\1\2\255 synthetic model bytes\r\n")
	Files.write(xml, SYNTHETIC_MODEL)
	local now = 0
	local env: Environment = {
		root = ".",
		config = Files.join(directory, "config.json"),
		receipts = Files.join(directory, "receipts"),
		gate = Files.join(directory, "gate.json"),
		model = model,
		xml = xml,
		manifest = manifest,
		publisher = Files.join(directory, "FacetPublisher.rbxl"),
		transport = fake.transport,
		decide = decider,
		apiKey = function(): string?
			return SELFTEST_KEY
		end,
		build = function(_publisher: boolean): Model.Manifest
			return Model.writeManifest(".", xml, model, manifest)
		end,
		toolchain = function(): Json.Object
			return ordered({ { "rojo", "selftest" }, { "lute", "selftest" } })
		end,
		clock = {
			now = function(): number
				return now
			end,
			sleep = function(seconds: number)
				now += seconds
			end,
		},
		say = function(line: string)
			table.insert(output, line)
		end,
	}
	return { directory = directory, env = env, output = output, fake = fake }
end

local function baseConfig(assetId: number?, route: string): Json.Object
	local decoded = Json.decode(Files.read(DEFAULT_CONFIG))
	local config = Json.asObject(decoded)
	if config == nil then
		error(DEFAULT_CONFIG .. " is not a JSON object", 0)
	end
	Json.set(config, "route", route)
	Json.set(config, "creator", ordered({ { "type", "user" }, { "id", 1234 } }))
	Json.set(config, "assetId", nullable(assetId))
	Json.set(config, "versions", Json.array())
	return config
end

local function argumentsFor(route: string, baseline: string?): Arguments
	local facts = real()
	return {
		confirm = true,
		route = route,
		allowRouteOverride = false,
		version = facts.version,
		commit = facts.commit,
		assetId = nil,
		creatorId = nil,
		creatorType = nil,
		actor = "selftest",
		baselineRevision = baseline,
		timeout = 1,
		poll = 1,
	}
end

local function within(test: Verify.Context, work: Work, body: () -> ())
	local before = Files.read(DEFAULT_CONFIG)
	test:defer(function()
		Verify.expect(Files.read(DEFAULT_CONFIG)):toBe(before)
		for _, line in work.output do
			Verify.expect(string.find(line, SELFTEST_KEY, 1, true) == nil)
				:toBeTrueWith("the API key reached the output: " .. line)
		end
	end)
	body()
end

local function invoke(work: Work, command: (Environment, Arguments) -> number, arguments: Arguments): number
	return guarded(work.env.say, function(): number
		return command(work.env, arguments)
	end)
end

local function storedReceipts(work: Work, version: string?): { Stored }
	local found: { Stored } = {}
	for _, stored in receipts(work.env.receipts) do
		if version == nil or raw(stored.receipt, "version") == version then
			table.insert(found, stored)
		end
	end
	return found
end

local function revisionOf(stored: Stored?): string?
	if stored == nil then
		return nil
	end
	return Json.stringField(Json.field(stored.receipt, "assetRevision"), "revisionId")
end

local function versionsPage(number: number): unknown
	return {
		assetVersions = {
			{
				path = ("assets/424242/versions/%d"):format(number),
				moderationResult = { moderationState = "Approved" },
			},
		},
	}
end

local function studioCase(
	test: Verify.Context,
	script: { Assets.Canned },
	baseline: string?,
	expectCode: number,
	revision: string?
): ()
	local work = workspace(test, script, noRefusals)
	within(test, work, function(): ()
		saveConfig(work.env.config, baseConfig(424242, "studio"))
		Files.write(work.env.gate, Json.pretty(gateDocument()))
		local code = invoke(work, cmdPublish, argumentsFor("studio", baseline))
		local written = storedReceipts(work, nil)
		if code ~= expectCode then
			error(("exit %d, expected %d"):format(code, expectCode), 0)
		end
		if revision == nil then
			Verify.expect(#written == 0):toBeTrueWith(("expected no receipt, found %d"):format(#written))
			return
		end
		Verify.expect(revisionOf(written[#written])):toBe(revision)
	end)
end

type Reading = { tier: string, status: string, treeDirty: boolean }

type Reader = { label: string, document: () -> string?, want: Reading? }

local function readEvidence(test: Verify.Context, document: string?, want: Reading?): ()
	local facts = real()
	local directory = Files.temporaryDirectory("facet-package-gate-")
	test:defer(function()
		Files.remove(directory)
	end)
	local path = Files.join(directory, "evidence.json")
	if document ~= nil then
		Files.write(path, document)
	end
	local ok, got = pcall(readGateEvidence, path)
	Files.remove(directory)
	if not ok then
		error("raised: " .. tostring(got), 0)
	end
	if want == nil then
		Verify.expect(got == nil)
			:toBeTrueWith("expected no evidence, got " .. (if got then str(got.status) else "none"))
		return
	end
	if got == nil then
		error("expected evidence, got none", 0)
	end
	if got.tier ~= want.tier or got.status ~= want.status or got.treeDirty ~= want.treeDirty then
		error(("read %s/%s/%s"):format(str(got.tier), str(got.status), str(got.treeDirty)), 0)
	end
	if got.schema ~= GATE_SCHEMA or got.commit ~= facts.commit or got.sourceHash ~= facts.sourceHash then
		error(("the evidence binding reads %s %s %s"):format(str(got.schema), str(got.commit), str(got.sourceHash)), 0)
	end
end

register = function(harness: Verify.Harness, prefix: string): ()
	for _, op in { "create", "publish" } do
		harness:case(prefix .. (("the all-good %s facts produce no refusal"):format(op)), {
			id = prefix .. (("the all-good %s facts produce no refusal"):format(op)),
			run = function(test: Verify.Context): ()
				local codes = codesOf(decide(goodFacts(op)))
				Verify.expect(codes):toEqual({})
			end,
		})
	end
	for _, refusal in REFUSAL_CASES do
		harness:case(prefix .. (("%s bites %s on %s"):format(refusal.op, refusal.code, refusal.label)), {
			id = prefix .. (("%s bites %s on %s"):format(refusal.op, refusal.code, refusal.label)),
			run = function(test: Verify.Context): ()
				local facts = goodFacts(refusal.op)
				refusal.change(facts)
				Verify.expect(codesOf(decide(facts))):toEqual({ refusal.code })
			end,
		})
	end
	harness:case(prefix .. "every guard has a refusal case", {
		id = prefix .. "every guard has a refusal case",
		run = function(test: Verify.Context): ()
			local covered: { [string]: boolean } = {}
			for _, refusal in REFUSAL_CASES do
				covered[refusal.code] = true
			end
			for _, guard in GUARDS do
				if not covered[guard[2]] then
					error("no case exercises " .. guard[2], 0)
				end
			end
		end,
	})
	harness:case(prefix .. "the guard table prints every verdict", {
		id = prefix .. "the guard table prints every verdict",
		run = function(test: Verify.Context): ()
			local lines: { string } = {}
			local facts = goodFacts("create")
			facts.gitDirty = true
			printVerdicts(function(line: string)
				table.insert(lines, line)
			end, decide(facts))
			local text = table.concat(lines, "\n")
			Verify.expect(string.find(text, "  [REFUSE] working tree clean", 1, true) ~= nil):toBeTrueWith(text)
			Verify.expect(string.find(text, "  [  ok  ] api key present (environment only)", 1, true) ~= nil)
				:toBeTrueWith(text)
			Verify.expect(string.find(text, "  [ n/a  ] moderation approved", 1, true) ~= nil):toBeTrueWith(text)
			Verify.expect(string.find(text, "REFUSALS (1)", 1, true) ~= nil):toBeTrueWith(text)
		end,
	})
	local function variant(overrides: () -> { { unknown } }): () -> string?
		return function(): string?
			return Json.pretty(gateDocument(overrides()))
		end
	end
	local function literal(text: string?): () -> string?
		return function(): string?
			return text
		end
	end
	local function acceptance(verdict: string, releasable: boolean, complete: boolean): () -> { { unknown } }
		return function(): { { unknown } }
			return { { "acceptance", gateAcceptance(verdict, releasable, complete) } }
		end
	end
	local readers: { Reader } = {
		{ label = "an absent file", document = literal(nil) },
		{
			label = "an outcome with no build binding",
			document = literal('{"schemaVersion": 1, "gate": "facet", "acceptance": {"releasable": true}}'),
		},
		{ label = "an unreadable file", document = literal("{ this is not json") },
		{
			label = "another gate's outcome",
			document = variant(function(): { { unknown } }
				return { { "gate", "another-gate" } }
			end),
		},
		{
			label = "the releasable outcome",
			document = variant(function(): { { unknown } }
				return {}
			end),
			want = { tier = "release", status = "PASS", treeDirty = false },
		},
		{
			label = "an outcome with an environment deferral",
			document = variant(acceptance("deferred", false, true)),
			want = { tier = "release", status = "deferred", treeDirty = false },
		},
		{
			label = "a focused outcome",
			document = variant(acceptance("selected", false, false)),
			want = { tier = "selected", status = "selected", treeDirty = false },
		},
		{
			label = "an outcome from a dirty tree",
			document = variant(function(): { { unknown } }
				return { { "build", gateBuild(false) } }
			end),
			want = { tier = "release", status = "PASS", treeDirty = true },
		},
	}
	for _, reader in readers do
		harness:case(prefix .. ("the gate evidence reader reads " .. reader.label), {
			id = prefix .. ("the gate evidence reader reads " .. reader.label),
			run = function(test: Verify.Context): ()
				readEvidence(test, reader.document(), reader.want)
			end,
		})
	end
	harness:case(prefix .. "real gate evidence clears every gate check", {
		id = prefix .. "real gate evidence clears every gate check",
		run = function(test: Verify.Context): ()
			local facts = real()
			local directory = Files.temporaryDirectory("facet-package-gate-")
			test:defer(function()
				Files.remove(directory)
			end)
			local path = Files.join(directory, "evidence.json")
			Files.write(path, Json.pretty(gateDocument()))
			local publish = goodFacts("publish")
			publish.argCommit = facts.commit
			publish.headCommit = facts.commit
			publish.sourceHash = facts.sourceHash
			publish.gate = readGateEvidence(path)
			Files.remove(directory)
			local gateCodes: { string } = {}
			for _, code in codesOf(decide(publish)) do
				if string.sub(code, 1, 5) == "gate-" then
					table.insert(gateCodes, code)
				end
			end
			Verify.expect(gateCodes):toEqual({})
		end,
	})
	harness:case(prefix .. "create --confirm under the real guards refuses with no transport call", {
		id = prefix .. "create --confirm under the real guards refuses with no transport call",
		run = function(test: Verify.Context): ()
			local work = workspace(test, {}, decide)
			within(test, work, function(): ()
				saveConfig(work.env.config, baseConfig(nil, "open-cloud"))
				local code = invoke(work, cmdCreate, argumentsFor("open-cloud", nil))
				Verify.expect(code):toBe(1)
				Verify.expect(#work.fake.calls):toBe(0)
			end)
		end,
	})
	harness:case(prefix .. "create against the fake records the asset id and one version", {
		id = prefix .. "create against the fake records the asset id and one version",
		run = function(test: Verify.Context): ()
			local work = workspace(test, {
				{
					method = "POST",
					fragment = "/v1/assets",
					status = 200,
					payload = { path = "operations/op-create", done = false },
				},
				{
					method = "GET",
					fragment = "/v1/operations/op-create",
					status = 200,
					payload = { path = "operations/op-create", done = false },
				},
				{
					method = "GET",
					fragment = "/v1/operations/op-create",
					status = 200,
					payload = { path = "operations/op-create", done = true, response = CREATED_ASSET },
				},
			}, noRefusals)
			within(test, work, function(): ()
				saveConfig(work.env.config, baseConfig(nil, "open-cloud"))
				Files.write(work.env.gate, Json.pretty(gateDocument()))
				local code = invoke(work, cmdCreate, argumentsFor("open-cloud", nil))
				local config = loadConfig(work.env.config)
				local polls = 0
				for _, call in work.fake.calls do
					if string.find(call.url, "/operations/", 1, true) ~= nil then
						polls += 1
					end
				end
				local versions = Json.arrayField(config, "versions") or {}
				local uploaded = work.fake.calls[1]
				Verify.expect(code):toBe(0)
				Verify.expect(raw(config, "assetId")):toBe(424242)
				Verify.expect(polls):toBe(2)
				Verify.expect(#versions):toBe(1)
				Verify.expect(Json.stringField(versions[1], "version")):toBe(real().version)
				Verify.expect(uploaded ~= nil and uploaded.bodyBytes > Files.size(work.env.model))
					:toBeTrueWith("the POST did not carry the model file")
			end)
		end,
	})
	harness:case(prefix .. "publish against the fake writes a receipt bound to its gate evidence", {
		id = prefix .. "publish against the fake writes a receipt bound to its gate evidence",
		run = function(test: Verify.Context): ()
			local published = table.clone(CREATED_ASSET)
			published.revisionId = "2"
			published.revisionCreateTime = "2026-08-30T01:00:00Z"
			local work = workspace(test, {
				{ method = "GET", fragment = "/v1/assets/424242", status = 200, payload = CREATED_ASSET },
				{
					method = "PATCH",
					fragment = "/v1/assets/424242",
					status = 200,
					payload = { path = "operations/op-publish", done = false },
				},
				{
					method = "GET",
					fragment = "/v1/operations/op-publish",
					status = 200,
					payload = { path = "operations/op-publish", done = true, response = published },
				},
			}, noRefusals)
			within(test, work, function(): ()
				local facts = real()
				saveConfig(work.env.config, baseConfig(424242, "open-cloud"))
				Files.write(work.env.gate, Json.pretty(gateDocument()))
				Files.write(
					Files.join(work.env.receipts, "0.9.0-0000000.json"),
					Json.encode(ordered({
						{ "schema", RECEIPT_SCHEMA },
						{ "version", "0.9.0" },
						{ "sourceHash", "old" .. string.rep("0", 61) },
						{ "operationPath", "operations/op-old" },
						{ "assetRevision", ordered({ { "revisionId", "1" } }) },
						{ "publishedAt", "2026-08-01T00:00:00Z" },
					}))
				)
				local code = invoke(work, cmdPublish, argumentsFor("open-cloud", nil))
				local written = storedReceipts(work, facts.version)
				local latest = written[#written]
				if code ~= 0 or latest == nil then
					error(("exit %d with %d receipts for %s"):format(code, #written, facts.version), 0)
				end
				local gateRun = Json.field(latest.receipt, "gateRun")
				Verify.expect(revisionOf(latest)):toBe("2")
				Verify.expect(Json.stringField(gateRun, "status")):toBe("PASS")
				Verify.expect(Json.stringField(gateRun, "commit")):toBe(facts.commit)
				Verify.expect(string.find(Files.read(latest.path), SELFTEST_KEY, 1, true) == nil)
					:toBeTrueWith("the API key reached a receipt")
			end)
		end,
	})
	local asset: Assets.Canned =
		{ method = "GET", fragment = "/v1/assets/424242", status = 200, payload = CREATED_ASSET }
	harness:case(prefix .. "studio create records an asset id only after reading it back", {
		id = prefix .. "studio create records an asset id only after reading it back",
		run = function(test: Verify.Context): ()
			local work = workspace(test, { asset }, noRefusals)
			within(test, work, function(): ()
				saveConfig(work.env.config, baseConfig(nil, "studio"))
				local arguments = argumentsFor("studio", nil)
				arguments.assetId = "424242"
				local code = invoke(work, cmdCreate, arguments)
				Verify.expect(code):toBe(0)
				Verify.expect(raw(loadConfig(work.env.config), "assetId")):toBe(424242)
				Verify.expect(#work.fake.calls):toBe(1)
			end)
		end,
	})
	harness:case(prefix .. "studio publish treats a pre-existing version as no publish", {
		id = prefix .. "studio publish treats a pre-existing version as no publish",
		run = function(test: Verify.Context): ()
			local script: { Assets.Canned } = { asset }
			for _ = 1, 6 do
				table.insert(
					script,
					{ method = "GET", fragment = "/versions", status = 200, payload = versionsPage(5) }
				)
			end
			studioCase(test, script, nil, 1, nil)
		end,
	})
	harness:case(prefix .. "studio publish records the edge from 5 to 6", {
		id = prefix .. "studio publish records the edge from 5 to 6",
		run = function(test: Verify.Context): ()
			studioCase(test, {
				asset,
				{ method = "GET", fragment = "/versions", status = 200, payload = versionsPage(5) },
				{ method = "GET", fragment = "/versions", status = 200, payload = versionsPage(6) },
			}, nil, 0, "6")
		end,
	})
	harness:case(prefix .. "studio publish refuses an unreadable version list", {
		id = prefix .. "studio publish refuses an unreadable version list",
		run = function(test: Verify.Context): ()
			studioCase(test, {
				asset,
				{ method = "GET", fragment = "/versions", status = 500, payload = { message = "boom" } },
			}, nil, 1, nil)
		end,
	})
	harness:case(prefix .. "studio publish uses --baseline-revision", {
		id = prefix .. "studio publish uses --baseline-revision",
		run = function(test: Verify.Context): ()
			studioCase(test, {
				asset,
				{ method = "GET", fragment = "/versions", status = 200, payload = versionsPage(9) },
			}, "8", 0, "9")
		end,
	})
	harness:case(prefix .. "the multipart body carries the model bytes unchanged", {
		id = prefix .. "the multipart body carries the model bytes unchanged",
		run = function(test: Verify.Context): ()
			local payload = "\0\1\2\255\r\n--not-a-boundary\r\n"
			local body, contentType = Assets.form({
				{ name = "request", value = '{"assetType": "Model"}' },
				{ name = "fileContent", value = payload, filename = "Facet.rbxm", contentType = RBXM_CONTENT_TYPE },
			}, "B")
			local expected = '--B\r\nContent-Disposition: form-data; name="request"\r\n\r\n{"assetType": "Model"}\r\n'
				.. '--B\r\nContent-Disposition: form-data; name="fileContent"; filename="Facet.rbxm"\r\n'
				.. "Content-Type: model/x-rbxm\r\n\r\n"
				.. payload
				.. "\r\n--B--\r\n"
			Verify.expect(contentType):toBe("multipart/form-data; boundary=B")
			Verify.expect(body == expected):toBeTrueWith("the multipart body differs from the expected bytes")
		end,
	})
	harness:case(prefix .. "the source hash uses slash paths and LF bodies", {
		id = prefix .. "the source hash uses slash paths and LF bodies",
		run = function(test: Verify.Context): ()
			Rule.within(test, {
				["src/init.luau"] = 'local VERSION = "1.2.3"\r\nreturn VERSION\r\n',
				["src/ui/button.luau"] = "return {}\n",
				["src/ui/button.verify.luau"] = "return nil\n",
				["src/ui/notes.md"] = "not a module\n",
			}, function(context: Rule.Context): ()
				local expected = Hash.sha256(
					'src/init.luau\nlocal VERSION = "1.2.3"\nreturn VERSION\nsrc/ui/button.luau\nreturn {}\n'
				)
				Verify.expect(Model.sourceFiles(context.root)):toEqual({ "src/init.luau", "src/ui/button.luau" })
				Verify.expect(Model.sourceHash(context.root)):toBe(expected)
				Verify.expect(Model.readVersion(context.root)):toBe("1.2.3")
			end)
		end,
	})
	harness:case(prefix .. "the manifest body hash matches the canonical instance list", {
		id = prefix .. "the manifest body hash matches the canonical instance list",
		run = function(test: Verify.Context): ()
			local instances = Model.walkText(table.concat({
				"<roblox>",
				'<Item class="ModuleScript"><Properties><string name="Name">Facet</string>',
				'<string name="Source"><![CDATA[return "caf\195\169"\r\n]]></string></Properties>',
				'<Item class="Folder"><Properties><string name="Name">b &amp; c</string></Properties></Item>',
				'<Item class="StringValue"><Properties><string name="Name"></string></Properties></Item>',
				"</Item>",
				"</roblox>",
			}))
			local paths: { string } = {}
			for _, instance in instances do
				table.insert(paths, instance.path)
			end
			Verify.expect(paths):toEqual({ "Facet", "Facet/StringValue", "Facet/b & c" })
			Verify.expect(instances[1].sourceSha256)
				:toBe("fb807541a393a9812f90a3151246f6e0c5ff9fa53e3a0a7a45210c6f46bae803")
			Verify.expect(Model.bodyHash(instances))
				:toBe("9abb63495b372f6883b1eb5a89fc99228a7deebe21f624f350d5d00c18860220")
		end,
	})
	harness:case(prefix .. "the tree inspection accepts the declared tree and names strays", {
		id = prefix .. "the tree inspection accepts the declared tree and names strays",
		run = function(test: Verify.Context): ()
			local instances: { Model.Instance } = {}
			local modules, folders = expectedTree(".")
			for path in modules do
				table.insert(instances, { path = path, className = "ModuleScript" })
			end
			for path in folders do
				table.insert(instances, { path = path, className = "Folder" })
			end
			for _, required in REQUIRED_DISTRIBUTION do
				table.insert(instances, { path = required[1], className = required[2] })
			end
			local manifest: Model.Manifest = {
				schema = Model.MANIFEST_SCHEMA,
				version = "0",
				sourceCommit = "0",
				sourceHash = "0",
				artifact = "x",
				artifactSha256 = "0",
				instanceCount = #instances,
				moduleCount = 0,
				bodyHash = "0",
				instances = instances,
			}
			local clean = inspectTree(".", manifest)
			table.insert(instances, { path = "Facet/tests/helper", className = "ModuleScript" })
			local dirty = inspectTree(".", manifest)
			Verify.expect(clean):toEqual({})
			Verify.expect(dirty):toEqual({
				"UNEXPECTED instance in the model: Facet/tests/helper (ModuleScript)",
				"FORBIDDEN in the distribution: Facet/tests/helper (segment 'tests')",
			})
		end,
	})
end

local command: Cli.Command = {
	name = "package",
	summary = "Build, inspect and release Facet's Roblox Package (create and publish are dry runs).",
	usage = USAGE,
	values = VALUES,
	register = register,
	run = run,
}

return command
