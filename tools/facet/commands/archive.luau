--!strict
local Gate = require("../lib/gate")
local Verify = require("../../vendor/verify/src/core")

local stringext = require("@std/stringext")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Hash = require("../lib/hash")
local Json = require("../lib/json")
local Run = require("../lib/run")

type Say = (string) -> ()

local USAGE = [[usage: lute run tools/facet archive private archive <path> [<path> ...] [--root DIR] [--source DIR]
       lute run tools/facet archive private verify [--root DIR]
       lute run tools/facet archive private list [--root DIR]
       lute run tools/facet archive --selftest

private -- the private archive for material that leaves the public tree.

  archive <path>...  copy repository-relative files or directories into the archive
                     and record each one in MANIFEST.json and SHA256SUMS
  verify             re-hash every archived file against MANIFEST.json and SHA256SUMS
  list               print each archived file with its hash, size and origin commit

  --root DIR    archive root (default: Facet-private-archive beside the library root)
  --source DIR  repository root the paths are relative to (default: the current directory)

Exit 0 = success; 1 = archive failure; 2 = bad invocation.]]

local MANIFEST_NAME = "MANIFEST.json"
local SUMS_NAME = "SHA256SUMS"
local SCHEMA = "facet-private-archive/1"
local BOOKKEEPING = { [MANIFEST_NAME] = true, [SUMS_NAME] = true }
local PRIVATE = "facet archive private"

local function defaultRoot(): string
	return Files.join(Files.parent(Files.cwd()), "Facet-private-archive")
end

local function sha256Of(path: string): string
	return Hash.sha256(Files.read(path))
end

local function headCommit(source: string): string
	local result = Run.git({ "-C", source, "rev-parse", "HEAD" })
	if not result.ok then
		return "unknown"
	end
	local trimmed = string.gsub(result.stdout, "^%s*(.-)%s*$", "%1")
	return trimmed
end

local function entriesOf(data: Json.Object): { Json.Object }
	local entries: { Json.Object } = {}
	local files = Json.asArray(data.files)
	if files == nil then
		error(("%s: %s has no files list"):format(PRIVATE, MANIFEST_NAME), 0)
	end
	for _, item in files do
		local entry = Json.asObject(item)
		if entry == nil or Json.stringField(entry, "path") == nil then
			error(("%s: %s holds an entry without a path"):format(PRIVATE, MANIFEST_NAME), 0)
		end
		table.insert(entries, entry)
	end
	return entries
end

local function loadManifest(root: string): Json.Object
	local path = Files.join(root, MANIFEST_NAME)
	if not Files.exists(path) then
		local fresh = Json.object()
		Json.set(fresh, "schema", SCHEMA)
		Json.set(fresh, "files", Json.array())
		return fresh
	end
	local decoded, problem = Json.tryDecode(Files.read(path))
	local data = Json.asObject(decoded)
	if data == nil then
		error(("%s: %s is not a JSON object: %s"):format(PRIVATE, path, problem or "wrong shape"), 0)
	end
	if data.schema == nil then
		Json.set(data, "schema", SCHEMA)
	end
	if data.files == nil then
		Json.set(data, "files", Json.array())
	end
	return data
end

local function pathOf(entry: Json.Object): string
	return Json.stringField(entry, "path") or ""
end

local function writeManifest(root: string, data: Json.Object, entries: { Json.Object })
	table.sort(entries, function(left: Json.Object, right: Json.Object): boolean
		return pathOf(left) < pathOf(right)
	end)
	local items: { unknown } = {}
	for _, entry in entries do
		table.insert(items, entry)
	end
	data.files = Json.array(items)
	Files.write(Files.join(root, MANIFEST_NAME), Json.encode(data, { indent = 2, sortKeys = true }) .. "\n")
	local sums: { string } = {}
	for _, entry in entries do
		table.insert(sums, ("%s  %s\n"):format(Json.stringField(entry, "sha256") or "", pathOf(entry)))
	end
	Files.write(Files.join(root, SUMS_NAME), table.concat(sums))
end

local function filesUnder(source: string, relative: string): { string }
	local absolute = Files.join(source, relative)
	if Files.isFile(absolute) then
		return { relative }
	end
	if not Files.isDirectory(absolute) then
		return {}
	end
	local found: { string } = {}
	for _, member in Files.walk(absolute, { skip = { [".git"] = true } }) do
		table.insert(found, if relative == "." then member else relative .. "/" .. member)
	end
	table.sort(found)
	return found
end

local function requestedRelative(requested: string): string?
	local cwd = Files.cwd()
	local absolute = Files.absolute(requested)
	if absolute == cwd then
		return "."
	end
	if not Files.within(absolute, cwd) then
		return nil
	end
	return Files.relative(absolute, cwd)
end

local function archive(paths: { string }, root: string, source: string, quiet: boolean, say: Say): (number, number)
	Files.makeDirectory(root)
	local data = loadManifest(root)
	local order: { string } = {}
	local byPath: { [string]: Json.Object } = {}
	for _, entry in entriesOf(data) do
		local path = pathOf(entry)
		if byPath[path] == nil then
			table.insert(order, path)
		end
		byPath[path] = entry
	end
	local commit = headCommit(source)
	local stamp = os.date("!%Y-%m-%dT%H:%M:%S+00:00")
	local missing: { string } = {}
	local copied = 0
	for _, requested in paths do
		local relative = requestedRelative(requested)
		if relative == nil then
			table.insert(missing, requested)
			continue
		end
		local members = filesUnder(source, relative)
		if #members == 0 then
			table.insert(missing, requested)
			continue
		end
		for _, member in members do
			local destination = Files.join(root, member)
			Files.copy(Files.join(source, member), destination)
			local entry = Json.object()
			Json.set(entry, "path", member)
			Json.set(entry, "sha256", sha256Of(destination))
			Json.set(entry, "bytes", Files.size(destination))
			Json.set(entry, "originCommit", commit)
			Json.set(entry, "archivedAt", stamp)
			if byPath[member] == nil then
				table.insert(order, member)
			end
			byPath[member] = entry
			copied += 1
			if not quiet then
				say(("  archived  %s  (%d bytes)"):format(member, Files.size(destination)))
			end
		end
	end
	local entries: { Json.Object } = {}
	for _, path in order do
		table.insert(entries, byPath[path])
	end
	writeManifest(root, data, entries)
	if #missing > 0 then
		for _, path in missing do
			say(("%s: NOT FOUND in %s: %s"):format(PRIVATE, source, path))
		end
		return 1, copied
	end
	if not quiet then
		say(("%s: %d file(s) archived into %s (manifest holds %d)"):format(PRIVATE, copied, root, #entries))
	end
	return 0, copied
end

local function verify(root: string, quiet: boolean, say: Say): number
	if not Files.isDirectory(root) then
		say(("%s: no archive at %s"):format(PRIVATE, root))
		return 1
	end
	local entries = entriesOf(loadManifest(root))
	local problems: { string } = {}
	for _, entry in entries do
		local name = pathOf(entry)
		local path = Files.join(root, name)
		if not Files.isFile(path) then
			table.insert(problems, ("MISSING   %s"):format(name))
			continue
		end
		local size = Files.size(path)
		local recordedBytes = Json.numberField(entry, "bytes")
		if size ~= recordedBytes then
			table.insert(
				problems,
				("SIZE      %s: manifest %s, on disk %d"):format(name, tostring(recordedBytes), size)
			)
		end
		local digest = sha256Of(path)
		local recordedDigest = Json.stringField(entry, "sha256") or ""
		if digest ~= recordedDigest then
			table.insert(
				problems,
				("CHECKSUM  %s: manifest %s…, on disk %s…"):format(
					name,
					string.sub(recordedDigest, 1, 16),
					string.sub(digest, 1, 16)
				)
			)
		end
	end
	local sumsPath = Files.join(root, SUMS_NAME)
	if not Files.isFile(sumsPath) then
		table.insert(problems, ("MISSING   %s"):format(SUMS_NAME))
	else
		local sums: { [string]: string } = {}
		for _, line in string.split(Files.text(sumsPath), "\n") do
			if line ~= "" then
				local separator = string.find(line, "  ", 1, true)
				if separator == nil then
					sums[""] = line
				else
					sums[string.sub(line, separator + 2)] = string.sub(line, 1, separator - 1)
				end
			end
		end
		local expected: { [string]: string } = {}
		local names: { string } = {}
		local seen: { [string]: boolean } = {}
		for _, entry in entries do
			local name = pathOf(entry)
			expected[name] = Json.stringField(entry, "sha256") or ""
			if not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
		for name in sums do
			if not seen[name] then
				seen[name] = true
				table.insert(names, name)
			end
		end
		table.sort(names)
		for _, name in names do
			if expected[name] ~= sums[name] then
				table.insert(problems, ("SUMS      %s: %s and %s disagree"):format(name, MANIFEST_NAME, SUMS_NAME))
			end
		end
	end
	local recorded: { [string]: boolean } = {}
	for _, entry in entries do
		recorded[pathOf(entry)] = true
	end
	local unrecorded = 0
	for _, relative in Files.walk(root) do
		if not BOOKKEEPING[relative] and not recorded[relative] then
			unrecorded += 1
		end
	end
	if #problems > 0 then
		say(("%s: verify FAILED — %d problem(s) in %s"):format(PRIVATE, #problems, root))
		for _, problem in problems do
			say("  " .. problem)
		end
		return 1
	end
	if not quiet then
		local total = 0
		for _, entry in entries do
			total += Json.numberField(entry, "bytes") or 0
		end
		say(("%s: verify OK — %d file(s), %d bytes, %s"):format(PRIVATE, #entries, total, root))
		if unrecorded > 0 then
			say(("  note: %d other file(s) in this archive root are not in this manifest"):format(unrecorded))
		end
	end
	return 0
end

local function show(root: string, say: Say): number
	local entries = entriesOf(loadManifest(root))
	for _, entry in entries do
		say(
			("%s  %9d  %s  %s"):format(
				Json.stringField(entry, "sha256") or "",
				Json.numberField(entry, "bytes") or 0,
				string.sub(Json.stringField(entry, "originCommit") or "", 1, 9),
				pathOf(entry)
			)
		)
	end
	say(("%s: %d file(s) in %s"):format(PRIVATE, #entries, root))
	return 0
end

local function collector(): ({ string }, Say)
	local lines: { string } = {}
	return lines, function(line: string)
		table.insert(lines, line)
	end
end

local function withDirectory(test: Verify.Context, body: (root: string) -> ())
	local root = Files.temporaryDirectory("facet-archive-case-")
	test:defer(function()
		Files.remove(root)
	end)
	body(root)
end

local function contains(lines: { string }, fragment: string): boolean
	for _, line in lines do
		if string.find(line, fragment, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "private: archive, verify, re-archive and planted faults", {
		id = prefix .. "private: archive, verify, re-archive and planted faults",
		run = function(test: Verify.Context): ()
			withDirectory(test, function(work: string): ()
				local source = Files.join(work, "repo")
				local root = Files.join(work, "archive")
				Files.write(Files.join(source, "vendor/Thing/init.luau"), "return {}\n")
				Files.write(Files.join(source, "vendor/Thing/NOTES.md"), "notes\n")
				Files.write(Files.join(source, "vendor/.git/HEAD"), "ref\n")
				Files.write(Files.join(source, "docs/one.md"), "one\n")
				local lines, say = collector()
				local code, copied = archive({ "vendor", "docs/one.md" }, root, source, true, say)
				local clean = verify(root, true, say)
				archive({ "vendor", "docs/one.md" }, root, source, true, say)
				local manifest = loadManifest(root)
				local entries = #entriesOf(manifest)
				local sums = Files.read(Files.join(root, SUMS_NAME))
				local planted = Files.join(root, "vendor/Thing/init.luau")
				Files.write(planted, "return {}\n-- tampered\n")
				local tampered = verify(root, true, say)
				Files.write(planted, "return {}\n")
				local restored = verify(root, true, say)
				Files.remove(Files.join(root, "docs/one.md"))
				local deleted = verify(root, true, say)
				local absent = archive({ "no/such/path" }, root, source, true, say)
				local outside = archive({ ".." }, root, source, true, say)
				Verify.expect(code):toBe(0)
				Verify.expect(copied):toBe(3)
				Verify.expect(clean):toBe(0)
				Verify.expect(entries):toBe(3)
				Verify.expect(string.find(sums, "  docs/one.md\n", 1, true) ~= nil)
					:toBeTrueWith("SHA256SUMS lacks docs/one.md")
				Verify.expect(Json.stringField(manifest, "schema")):toBe(SCHEMA)
				Verify.expect(tampered ~= 0):toBeTrueWith("a planted checksum mismatch verified")
				Verify.expect(contains(lines, "CHECKSUM  vendor/Thing/init.luau")):toBeTrueWith("no CHECKSUM line")
				Verify.expect(restored):toBe(0)
				Verify.expect(deleted ~= 0):toBeTrueWith("a deleted archived file verified")
				Verify.expect(absent ~= 0):toBeTrueWith("archiving a missing path passed")
				Verify.expect(outside ~= 0):toBeTrueWith("archiving the parent directory passed")
			end)
		end,
	})
	harness:case(prefix .. "private: SHA256SUMS disagreement and unrecorded files", {
		id = prefix .. "private: SHA256SUMS disagreement and unrecorded files",
		run = function(test: Verify.Context): ()
			withDirectory(test, function(work: string): ()
				local source = Files.join(work, "repo")
				local root = Files.join(work, "archive")
				Files.write(Files.join(source, "a.txt"), "a\n")
				local lines, say = collector()
				archive({ "a.txt" }, root, source, true, say)
				Files.write(Files.join(root, "stray.txt"), "stray\n")
				local noted = verify(root, false, say)
				Files.write(Files.join(root, SUMS_NAME), string.rep("0", 64) .. "  a.txt\n")
				local disagreed = verify(root, true, say)
				Files.remove(Files.join(root, SUMS_NAME))
				local missingSums = verify(root, true, say)
				local listed, listSay = collector()
				show(root, listSay)
				Verify.expect(noted):toBe(0)
				Verify.expect(contains(lines, "note: 1 other file(s)")):toBeTrueWith("no unrecorded note")
				Verify.expect(disagreed):toBe(1)
				Verify.expect(contains(lines, "SUMS      a.txt: MANIFEST.json and SHA256SUMS disagree"))
					:toBeTrueWith("no SUMS line")
				Verify.expect(missingSums):toBe(1)
				Verify.expect(contains(listed, "          2  ")):toBeTrueWith("list lacks the padded size")
				Verify.expect(contains(listed, "1 file(s) in")):toBeTrueWith("no list summary")
			end)
		end,
	})
end

local function runPrivate(invocation: Cli.Invocation): number
	local action = invocation.positional[2]
	local root = Cli.flag(invocation, "root") or defaultRoot()
	local source = Cli.flag(invocation, "source") or Files.cwd()
	local paths: { string } = {}
	for index = 3, #invocation.positional do
		table.insert(paths, invocation.positional[index])
	end
	local ok, outcome = pcall(function(): number
		if action == "archive" then
			if #paths == 0 then
				print(("%s: archive needs at least one path"):format(PRIVATE))
				return 1
			end
			local code = archive(paths, root, source, false, print)
			return code
		elseif action == "verify" then
			return verify(root, false, print)
		elseif action == "list" then
			return show(root, print)
		end
		print(USAGE)
		return 2
	end)
	if not ok then
		print(tostring(outcome))
		return 1
	end
	return outcome
end

local function run(invocation: Cli.Invocation): number
	if Cli.switch(invocation, "selftest") then
		return Gate.selftest("tools/commands", "tools/commands::archive::")
	end
	local area = invocation.positional[1]
	if area == "private" then
		local unknown = Cli.unknownFlags(invocation, { "root", "source" })
		if unknown ~= nil then
			print(("%s: unrecognized argument %s"):format(PRIVATE, unknown))
			return 2
		end
		return runPrivate(invocation)
	end
	print(USAGE)
	return 2
end

local command: Cli.Command = {
	name = "archive",
	summary = "Keep the private archive (private archive|verify|list).",
	usage = USAGE,
	values = { "root", "source" },
	register = register,
	run = run,
}

return command
