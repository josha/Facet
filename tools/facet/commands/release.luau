--!strict

local process = require("@std/process")
local Case = require("../lib/case")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Run = require("../lib/run")

local USAGE = [[usage: lute run tools/facet release <version> <commit> [extra package publish flags...]

Builds and publishes Facet <version> from <commit> in a temporary git worktree:
the release gate (lune run tools/lune/verify release), then
lute run tools/facet package build and package publish --confirm.
It refuses an unknown commit, a dirty tree, a missing ROBLOX_API_KEY and an
unconfigured asset id. It never pushes.]]

local CONFIG = "package/facet-package.json"
local RECEIPTS = "package/receipts"
local MUTABLE = { "assetId", "versions" }

export type Facts = {
	commit: string,
	commitKnown: boolean,
	dirty: string,
	apiKey: string?,
	configProblem: string?,
	assetId: string?,
}

export type Receipt = { name: string, body: string }

local Release = {}

function Release.tail(argv: { string }, command: string): { string }?
	for index = 2, #argv do
		if argv[index] == command then
			return table.move(argv, index + 1, #argv, 1, {})
		end
	end
	return nil
end

function Release.rebuild(invocation: Cli.Invocation): { string }
	local arguments = table.clone(invocation.positional)
	local names: { string } = {}
	for name in invocation.flags do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local values = invocation.repeated[name]
		if values ~= nil then
			for _, value in values do
				table.insert(arguments, `--{name}={value}`)
			end
		else
			table.insert(arguments, `--{name}`)
		end
	end
	return arguments
end

function Release.split(arguments: { string }): (string?, string?, { string })
	if #arguments < 2 then
		return nil, nil, {}
	end
	return arguments[1], arguments[2], table.move(arguments, 3, #arguments, 1, {})
end

function Release.assetId(value: unknown): string?
	if type(value) == "number" then
		if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
			return ("%d"):format(value)
		end
		return tostring(value)
	elseif type(value) == "string" and value ~= "" then
		return value
	end
	return nil
end

function Release.guard(facts: Facts): string?
	if not facts.commitKnown then
		return `'{facts.commit}' is not an object in this repository`
	elseif facts.dirty ~= "" then
		return "the working tree is dirty; a release is built from a commit, not from a desk"
	elseif facts.apiKey == nil or facts.apiKey == "" then
		return "ROBLOX_API_KEY is not set in the environment (it is never read from a file)"
	elseif facts.configProblem ~= nil then
		return `cannot read {CONFIG}: {facts.configProblem}`
	elseif facts.assetId == nil then
		return `{CONFIG} records no assetId — run lute run tools/facet package create first`
	end
	return nil
end

function Release.fresh(receipts: { Receipt }, startedAt: string): { Receipt }
	local found: { Receipt } = {}
	for _, receipt in receipts do
		if string.sub(receipt.name, -5) ~= ".json" then
			continue
		end
		local document = Json.tryDecode(receipt.body)
		local published = Json.field(document, "publishedAt")
		local stamp = if published == nil then "" else tostring(published)
		if stamp >= startedAt then
			table.insert(found, receipt)
		end
	end
	return found
end

function Release.moved(mine: unknown, theirs: unknown): { string }
	local keys: { [string]: boolean } = {}
	local mineObject: Json.Object = Json.asObject(mine) or {}
	local theirObject: Json.Object = Json.asObject(theirs) or {}
	for key in mineObject do
		keys[key] = true
	end
	for key in theirObject do
		keys[key] = true
	end
	local moved: { string } = {}
	for key in keys do
		if
			table.find(MUTABLE, key) == nil
			and Json.canonical({ mineObject[key] }) ~= Json.canonical({ theirObject[key] })
		then
			table.insert(moved, key)
		end
	end
	table.sort(moved)
	return moved
end

local function facts(commit: string): Facts
	local known = Run.git({ "cat-file", "-t", commit }).ok
	local status = Run.git({ "status", "--porcelain" })
	local dirty = string.gsub(status.stdout, "%s+$", "")
	if not status.ok then
		dirty = "git status failed: " .. status.stderr
	end
	local configProblem: string? = nil
	local assetId: string? = nil
	if not Files.isFile(CONFIG) then
		configProblem = "the file does not exist"
	else
		local document, problem = Json.tryDecode(Files.read(CONFIG))
		configProblem = problem
		assetId = Release.assetId(Json.field(document, "assetId"))
	end
	return {
		commit = commit,
		commitKnown = known,
		dirty = dirty,
		apiKey = Run.env("ROBLOX_API_KEY"),
		configProblem = configProblem,
		assetId = assetId,
	}
end

local function refuse(message: string, code: number?): number
	print("release: " .. message)
	return code or 1
end

local function studioSteps(assetId: string, version: string, commit: string, receipt: string): string
	return table.concat({
		"STUDIO VERIFICATION — owed before this release counts as verified",
		"  1. Open a clean Studio place.",
		`  2. Insert the package by id ({assetId}) from Toolbox > Inventory > My Packages.`,
		"  3. Move it to ReplicatedStorage and confirm the root is one ModuleScript named Facet",
		"     with a PackageLink beside it.",
		"  4. Read Facet.Distribution's Version / SourceCommit / SourceHash attributes and",
		`     compare them with this release: {version} / {commit}.`,
		"  5. require() it and exercise mount, theme, input, a reactive update and teardown.",
		"  6. Confirm PackageLink.VersionNumber advanced and Status reads Up To Date.",
		"  7. In a second place holding an AutoUpdate copy, confirm it picks the new version up",
		"     on place-open; in a third holding a locally MODIFIED copy, confirm it is reported",
		"     as modified and skipped rather than overwritten.",
		"Then record it:",
		`  lute run tools/facet package stamp --receipt {receipt} \\`,
		'      --studio-verified --by "<who>" --notes "<what you saw>"',
	}, "\n")
end

local function publish(version: string, commit: string, assetId: string, extra: { string }): number
	local fullCommit = Run.gitOutput({ "rev-parse", commit }) or commit
	local work = Files.temporaryDirectory("facet-release-")
	local function finish(code: number): number
		Run.git({ "worktree", "remove", "--force", work })
		if Files.isDirectory(work) then
			Files.remove(work)
		end
		return code
	end
	print(`release: Facet {version} at {fullCommit}`)
	print(`release: worktree {work}`)
	if not Run.git({ "worktree", "add", "--detach", work, fullCommit }).ok then
		return finish(1)
	end
	print("release: gate = lune run tools/lune/verify release")
	if not Run.inherit({ "lune", "run", "tools/lune/verify", "release" }, { cwd = work }).ok then
		return finish(1)
	end
	print("release: gate PASS")
	local lute = Run.lute()
	if not Run.capture({ lute, "run", "tools/facet", "package", "build" }, { cwd = work }).ok then
		return finish(1)
	end
	local startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
	local command = {
		lute,
		"run",
		"tools/facet",
		"package",
		"publish",
		"--confirm",
		"--version",
		version,
		"--commit",
		fullCommit,
		"--asset-id",
		assetId,
	}
	table.move(extra, 1, #extra, #command + 1, command)
	if not Run.inherit(command, { cwd = work }).ok then
		return finish(1)
	end
	print("release: publish exited 0")

	Files.makeDirectory(RECEIPTS)
	local written: { Receipt } = {}
	local source = Files.join(work, RECEIPTS)
	for _, entry in Files.list(source) do
		if entry.type == "file" then
			table.insert(written, { name = entry.name, body = Files.read(Files.join(source, entry.name)) })
		end
	end
	local latest: string? = nil
	for _, receipt in Release.fresh(written, startedAt) do
		local target = `{RECEIPTS}/{receipt.name}`
		if Files.isFile(target) and Files.read(target) ~= receipt.body then
			print(
				`release: {receipt.name} already exists in the main tree with different content — refusing to overwrite`
			)
			print(`release: the worktree's copy is at {source}/{receipt.name}`)
			return 1
		end
		Files.write(target, receipt.body)
		print(`release: receipt {target}`)
		latest = target
	end
	if latest == nil then
		print(`release: publish exited 0 but wrote no receipt dated at or after {startedAt}`)
		return 1
	end

	local updated = Files.read(Files.join(work, CONFIG))
	local moved = Release.moved((Json.tryDecode(Files.read(CONFIG))), (Json.tryDecode(updated)))
	if #moved > 0 then
		print(`release: the worktree's {CONFIG} disagrees with the main tree outside assetId and`)
		print(`release: versions ({table.concat(moved, ",")}); refusing to copy it back. Reconcile by hand.`)
		return 1
	end
	Files.write(CONFIG, updated)
	print(`release: {CONFIG} updated`)
	print(studioSteps(assetId, version, fullCommit, latest))
	print("release: done. Nothing was pushed; commit the receipt yourself.")
	return finish(0)
end

local function run(invocation: Cli.Invocation): number
	local arguments = Release.tail(process.args, invocation.command) or Release.rebuild(invocation)
	local version, commit, extra = Release.split(arguments)
	if version == nil or commit == nil then
		return refuse("usage: lute run tools/facet release <version> <commit> [extra package publish flags...]", 2)
	end
	local known = facts(commit)
	local refusal = Release.guard(known)
	if refusal ~= nil then
		if known.commitKnown and known.dirty ~= "" then
			print(known.dirty)
		end
		return refuse(refusal)
	end
	return publish(version, commit, known.assetId or "", extra)
end

local function ready(): Facts
	return {
		commit = "abc1234",
		commitKnown = true,
		dirty = "",
		apiKey = "set",
		configProblem = nil,
		assetId = "123",
	}
end

local function refusedWith(changes: (Facts) -> (), fragment: string): string?
	local facts = ready()
	changes(facts)
	local refusal = Release.guard(facts)
	if refusal == nil then
		return "the guard accepted facts that need the refusal '" .. fragment .. "'"
	end
	return Case.expect(
		string.find(refusal, fragment, 1, true) ~= nil,
		`expected a refusal naming '{fragment}', got '{refusal}'`
	)
end

local function cases(): { Case.Case }
	return {
		{
			name = "clean facts pass the guard",
			run = function()
				return Case.equal(Release.guard(ready()), nil, "refusal")
			end,
		},
		{
			name = "an unknown commit is refused before the tree is inspected",
			run = function()
				return refusedWith(function(facts: Facts)
					facts.commitKnown = false
					facts.dirty = " M src/init.luau"
					facts.apiKey = nil
				end, "'abc1234' is not an object in this repository")
			end,
		},
		{
			name = "a dirty tree is refused before the key is read",
			run = function()
				return refusedWith(function(facts: Facts)
					facts.dirty = "?? stray.txt"
					facts.apiKey = nil
				end, "the working tree is dirty")
			end,
		},
		{
			name = "a missing or empty ROBLOX_API_KEY is refused",
			run = function()
				return Case.first(
					refusedWith(function(facts: Facts)
						facts.apiKey = nil
					end, "ROBLOX_API_KEY is not set"),
					refusedWith(function(facts: Facts)
						facts.apiKey = ""
					end, "ROBLOX_API_KEY is not set")
				)
			end,
		},
		{
			name = "an unreadable config and a config without an asset id are refused",
			run = function()
				return Case.first(
					refusedWith(function(facts: Facts)
						facts.configProblem = "the file does not exist"
						facts.assetId = nil
					end, "cannot read package/facet-package.json"),
					refusedWith(function(facts: Facts)
						facts.assetId = nil
					end, "records no assetId")
				)
			end,
		},
		{
			name = "asset ids are read from numbers and nonempty strings only",
			run = function()
				return Case.first(
					Case.equal(Release.assetId(123456789012), "123456789012", "number"),
					Case.equal(Release.assetId("987"), "987", "string"),
					Case.equal(Release.assetId(""), nil, "empty"),
					Case.equal(Release.assetId(Json.null), nil, "null"),
					Case.equal(Release.assetId(nil), nil, "missing")
				)
			end,
		},
		{
			name = "the version, the commit and the extra flags are split verbatim",
			run = function()
				local raw = Release.tail(
					{ "tools/facet", "release", "1.2.0", "abc", "--route", "open-cloud", "--allow-route-override" },
					"release"
				)
				local version, commit, extra = Release.split(raw or {})
				local short = Release.split({ "1.2.0" })
				return Case.first(
					Case.equal(version, "1.2.0", "version"),
					Case.equal(commit, "abc", "commit"),
					Case.same(extra, { "--route", "open-cloud", "--allow-route-override" }, "extra"),
					Case.equal(short, nil, "a single argument"),
					Case.equal(Release.tail({ "tools/facet", "check" }, "release"), nil, "another command")
				)
			end,
		},
		{
			name = "only receipts published at or after the start are copied back",
			run = function()
				local fresh = Release.fresh({
					{ name = "old.json", body = '{"publishedAt": "2026-01-01T00:00:00Z"}' },
					{ name = "same.json", body = '{"publishedAt": "2026-02-02T10:00:00Z"}' },
					{ name = "new.json", body = '{"publishedAt": "2026-02-02T10:00:01Z"}' },
					{ name = "notes.txt", body = '{"publishedAt": "2027-01-01T00:00:00Z"}' },
					{ name = "unstamped.json", body = "{}" },
				}, "2026-02-02T10:00:00Z")
				local names: { string } = {}
				for _, receipt in fresh do
					table.insert(names, receipt.name)
				end
				return Case.same(names, { "same.json", "new.json" })
			end,
		},
		{
			name = "the config is copied back only when assetId and versions alone moved",
			run = function()
				local mine = Json.decode('{"assetId": 1, "versions": [], "route": "studio", "creator": {"id": 2}}')
				local same = Json.decode('{"creator": {"id": 2}, "route": "studio", "assetId": 1, "versions": [1]}')
				local moved = Json.decode('{"assetId": 1, "versions": [], "route": "open-cloud", "extra": true}')
				return Case.first(
					Case.same(Release.moved(mine, same), {}, "assetId and versions"),
					Case.same(Release.moved(mine, moved), { "creator", "extra", "route" }, "other keys")
				)
			end,
		},
	}
end

local command: Cli.Command = {
	name = "release",
	summary = "Gate, build and publish a release from a commit in a temporary worktree.",
	usage = USAGE,
	cases = cases,
	run = run,
}

return command
