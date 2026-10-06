--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")
local serde = require("@lune/serde")

local function refuse(message: string, code: number?): never
	print("release: " .. message)
	return process.exit(code or 1)
end

local function capture(argv: { string }, cwd: string?): (boolean, string)
	local arguments = table.clone(argv)
	local command = table.remove(arguments, 1) :: string
	local result = process.exec(command, arguments, { cwd = cwd })
	return result.ok, (string.gsub(result.stdout, "%s+$", ""))
end

local function run(argv: { string }, cwd: string, quiet: boolean?): boolean
	local arguments = table.clone(argv)
	local command = table.remove(arguments, 1) :: string
	return process.exec(command, arguments, { cwd = cwd, stdio = if quiet then "default" else "inherit" }).ok
end

local arguments = table.clone(process.args)
if #arguments < 2 then
	refuse("usage: lune run tools/lune/release <version> <commit> [extra package.py flags...]", 2)
end
local version = table.remove(arguments, 1) :: string
local commit = table.remove(arguments, 1) :: string
local repo = process.cwd

if not capture({ "git", "cat-file", "-t", commit }) then
	refuse(`'{commit}' is not an object in this repository`)
end
local _, dirty = capture({ "git", "status", "--porcelain" })
if dirty ~= "" then
	print(dirty)
	refuse("the working tree is dirty; a release is built from a commit, not from a desk")
end
if (process.env.ROBLOX_API_KEY or "") == "" then
	refuse("ROBLOX_API_KEY is not set in the environment (it is never read from a file)")
end
local config = "package/facet-package.json"
local assetId = serde.decode("json", fs.readFile(config)).assetId
if assetId == nil or assetId == "" then
	refuse(`{config} records no assetId — run python3 tools/package.py create first`)
end
local _, fullCommit = capture({ "git", "rev-parse", commit })
local _, temporary = capture({ "mktemp", "-d", `{process.env.TMPDIR or "/tmp"}/facet-release-XXXXXX` })
local work = temporary

local function finish(code: number): never
	process.exec("git", { "worktree", "remove", "--force", work })
	if fs.isDir(work) then
		fs.removeDir(work)
	end
	return process.exit(code)
end

print(`release: Facet {version} at {fullCommit}`)
print(`release: worktree {work}`)
if not run({ "git", "worktree", "add", "--detach", work, fullCommit }, repo, true) then
	finish(1)
end
print("release: gate = lune run tools/lune/verify release")
if not run({ "lune", "run", "tools/lune/verify", "release" }, work) then
	finish(1)
end
print("release: gate PASS")
if not run({ "python3", "tools/package.py", "build" }, work, true) then
	finish(1)
end
local startedAt = os.date("!%Y-%m-%dT%H:%M:%SZ")
local publish = {
	"python3",
	"tools/package.py",
	"publish",
	"--confirm",
	"--version",
	version,
	"--commit",
	fullCommit,
	"--asset-id",
	tostring(assetId),
}
table.move(arguments, 1, #arguments, #publish + 1, publish)
if not run(publish, work) then
	finish(1)
end
print("release: publish exited 0")

fs.writeDir("package/receipts")
local latest: string? = nil
local receipts = `{work}/package/receipts`
local names: { string } = if fs.isDir(receipts) then fs.readDir(receipts) else {}
for _, name in names do
	local source = `{receipts}/{name}`
	if string.match(name, "%.json$") then
		local body = fs.readFile(source)
		if tostring(serde.decode("json", body).publishedAt or "") >= startedAt then
			local target = `package/receipts/{name}`
			if fs.isFile(target) and fs.readFile(target) ~= body then
				print(
					`release: {name} already exists in the main tree with different content — refusing to overwrite`
				)
				print(`release: the worktree's copy is at {source}`)
				process.exit(1)
			end
			fs.writeFile(target, body)
			print(`release: receipt {target}`)
			latest = target
		end
	end
end
if latest == nil then
	print(`release: publish exited 0 but wrote no receipt dated at or after {startedAt}`)
	process.exit(1)
end

local MUTABLE = { "assetId", "versions" }
local mine = serde.decode("json", fs.readFile(config))
local theirs = serde.decode("json", fs.readFile(`{work}/{config}`))
local moved = {}
local keys = {}
for key in mine do
	keys[key] = true
end
for key in theirs do
	keys[key] = true
end
for key in keys do
	if
		not table.find(MUTABLE, key)
		and serde.encode("json", { mine[key] }) ~= serde.encode("json", { theirs[key] })
	then
		table.insert(moved, key)
	end
end
if #moved > 0 then
	table.sort(moved)
	print(`release: the worktree's {config} disagrees with the main tree outside assetId and`)
	print(`release: versions ({table.concat(moved, ",")}); refusing to copy it back. Reconcile by hand.`)
	process.exit(1)
end
fs.writeFile(config, fs.readFile(`{work}/{config}`))
print(`release: {config} updated`)

print(table.concat({
	"STUDIO VERIFICATION — owed before this release counts as verified",
	"  1. Open a clean Studio place.",
	`  2. Insert the package by id ({assetId}) from Toolbox > Inventory > My Packages.`,
	"  3. Move it to ReplicatedStorage and confirm the root is one ModuleScript named Facet",
	"     with a PackageLink beside it.",
	"  4. Read Facet.Distribution's Version / SourceCommit / SourceHash attributes and",
	`     compare them with this release: {version} / {fullCommit}.`,
	"  5. require() it and exercise mount, theme, input, a reactive update and teardown.",
	"  6. Confirm PackageLink.VersionNumber advanced and Status reads Up To Date.",
	"  7. In a second place holding an AutoUpdate copy, confirm it picks the new version up",
	"     on place-open; in a third holding a locally MODIFIED copy, confirm it is reported",
	"     as modified and skipped rather than overwritten.",
	"Then record it:",
	`  python3 tools/package.py stamp --receipt {latest} \\`,
	'      --studio-verified --by "<who>" --notes "<what you saw>"',
}, "\n"))
print("release: done. Nothing was pushed; commit the receipt yourself.")
finish(0)
