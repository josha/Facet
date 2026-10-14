--!strict

local Case = require("../lib/case")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Hash = require("../lib/hash")
local Json = require("../lib/json")
local Run = require("../lib/run")

type Say = (string) -> ()

type Link = { start: number, finish: number, label: string, target: string }

local USAGE = [[usage: lute run tools/facet archive private archive <path> [<path> ...] [--root DIR] [--source DIR]
       lute run tools/facet archive private verify [--root DIR]
       lute run tools/facet archive private list [--root DIR]
       lute run tools/facet archive relink --check
       lute run tools/facet archive relink --fix
       lute run tools/facet archive --selftest

private -- the private archive for material that leaves the public tree.

  archive <path>...  copy repository-relative files or directories into the archive
                     and record each one in MANIFEST.json and SHA256SUMS
  verify             re-hash every archived file against MANIFEST.json and SHA256SUMS
  list               print each archived file with its hash, size and origin commit

  --root DIR    archive root (default: Facet-private-archive beside the library root)
  --source DIR  repository root the paths are relative to (default: the current directory)

relink -- turn links into privately archived material into plain text.

WHY THIS EXISTS. Some material does not go public: the decision records, the
written-up defects, the internal plans, the handoff notes, the raw research
files, the stage evidence, and the comparison documents that move into the
private archive. A link whose target is not in the repository is worse than no
link: a reader clicks it, gets a 404, and learns nothing about why the sentence
is true.

The repair is mechanical and deliberately minimal. A markdown link whose target
is in the archived set becomes:

    <link text> `<old path>` (archived privately)

...and nothing else on the line changes. The sentence keeps its wording and its
citation; only the false promise that you can open the file goes away. When the
link text is itself the path in a code span, the path is not repeated.

    lute run tools/facet archive relink --check   # report every offender, exit 1 if any
    lute run tools/facet archive relink --fix     # rewrite them, print before/after counts

Exit 0 = clean (or fixed); 1 = offenders found by --check; 2 = bad invocation.]]

local MANIFEST_NAME = "MANIFEST.json"
local SUMS_NAME = "SHA256SUMS"
local SCHEMA = "facet-private-archive/1"
local BOOKKEEPING = { [MANIFEST_NAME] = true, [SUMS_NAME] = true }
local PRIVATE = "facet archive private"
local RELINK = "facet archive relink"

local SCANNED_DIRS = { "docs/guide", "docs/extending", "docs/reference" }
local ARCHIVED_PREFIXES = {
	"docs/adr/",
	"docs/lessons/",
	"docs/plans/",
	"docs/handoff/",
	"docs/research/",
	"artifacts/",
	".superpowers/",
	"vendor/",
}
local ARCHIVED_FILES = { "docs/INVENTORY.md", "ui_todo.md", "sweep.luau" }
local PUBLIC_REFERENCE = { "docs/reference/api.md", "docs/reference/constitution.md" }
local NOTE = "(archived privately)"

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

local function whitespaceAt(source: string, index: number): number
	local byte = string.byte(source, index)
	if byte == nil then
		return 0
	end
	if byte == 32 or (byte >= 9 and byte <= 13) or (byte >= 28 and byte <= 31) then
		return 1
	end
	local second, third = string.byte(source, index + 1, index + 2)
	if byte == 0xC2 and (second == 0x85 or second == 0xA0) then
		return 2
	end
	if third == nil then
		return 0
	end
	if byte == 0xE1 and second == 0x9A and third == 0x80 then
		return 3
	end
	if
		byte == 0xE2
		and second == 0x80
		and ((third >= 0x80 and third <= 0x8A) or third == 0xA8 or third == 0xA9 or third == 0xAF)
	then
		return 3
	end
	if byte == 0xE2 and second == 0x81 and third == 0x9F then
		return 3
	end
	if byte == 0xE3 and second == 0x80 and third == 0x80 then
		return 3
	end
	return 0
end

local function strip(text: string): string
	local first = 1
	while first <= #text do
		local width = whitespaceAt(text, first)
		if width == 0 then
			break
		end
		first += width
	end
	local last = #text
	while last >= first do
		if whitespaceAt(text, last) == 1 then
			last -= 1
		elseif last - 1 >= first and whitespaceAt(text, last - 1) == 2 then
			last -= 2
		elseif last - 2 >= first and whitespaceAt(text, last - 2) == 3 then
			last -= 3
		else
			break
		end
	end
	return string.sub(text, first, last)
end

local function stripBackticks(text: string): string
	local trimmed = string.match(text, "^`*(.-)`*$") or text
	return trimmed
end

local function linkAt(source: string, start: number): Link?
	local index = start + 1
	while true do
		local character = string.sub(source, index, index)
		if character == "" then
			return nil
		elseif character == "]" then
			break
		elseif character == "[" then
			local close = index + 1
			while true do
				local inner = string.sub(source, close, close)
				if inner == "" or inner == "[" then
					return nil
				elseif inner == "]" then
					break
				end
				close += 1
			end
			index = close + 1
		else
			index += 1
		end
	end
	local labelEnd = index
	if string.sub(source, labelEnd + 1, labelEnd + 1) ~= "(" then
		return nil
	end
	local targetStart = labelEnd + 2
	local cursor = targetStart
	while true do
		local character = string.sub(source, cursor, cursor)
		if character == "" or character == ")" or whitespaceAt(source, cursor) > 0 then
			break
		end
		cursor += 1
	end
	if cursor == targetStart then
		return nil
	end
	local target = string.sub(source, targetStart, cursor - 1)
	local finish: number
	if string.sub(source, cursor, cursor) == ")" then
		finish = cursor
	else
		local spaced = cursor
		while whitespaceAt(source, spaced) > 0 do
			spaced += whitespaceAt(source, spaced)
		end
		if spaced == cursor or string.sub(source, spaced, spaced) ~= '"' then
			return nil
		end
		local closing = string.find(source, '"', spaced + 1, true)
		if closing == nil or string.sub(source, closing + 1, closing + 1) ~= ")" then
			return nil
		end
		finish = closing + 1
	end
	return { start = start, finish = finish, label = string.sub(source, start + 1, labelEnd - 1), target = target }
end

local function links(source: string): { Link }
	local found: { Link } = {}
	local index = 1
	while true do
		local start = string.find(source, "[", index, true)
		if start == nil then
			break
		end
		local link = linkAt(source, start)
		if link ~= nil then
			table.insert(found, link)
			index = link.finish + 1
		else
			index = start + 1
		end
	end
	return found
end

local function normalizePath(path: string): string
	local parts: { string } = {}
	for _, part in string.split(path, "/") do
		if part == "" or part == "." then
			continue
		end
		if part == ".." then
			if #parts > 0 then
				table.remove(parts)
			end
			continue
		end
		table.insert(parts, part)
	end
	return table.concat(parts, "/")
end

local function dirname(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function basename(path: string): string
	return string.match(path, "([^/]*)$") or path
end

local function resolve(path: string, document: string): string
	if string.sub(path, 1, 1) == "/" then
		local rooted = string.gsub(path, "^/+", "")
		return normalizePath(rooted)
	end
	return normalizePath(dirname(document) .. "/" .. path)
end

local function startsWith(text: string, prefix: string): boolean
	return string.sub(text, 1, #prefix) == prefix
end

local function beforeFragment(target: string): string
	local hash = string.find(target, "#", 1, true)
	return if hash then string.sub(target, 1, hash - 1) else target
end

local function isArchived(target: string, document: string): boolean
	for _, scheme in { "http://", "https://", "mailto:", "#" } do
		if startsWith(target, scheme) then
			return false
		end
	end
	local path = beforeFragment(target)
	if path == "" then
		return false
	end
	local resolved = resolve(path, document)
	if table.find(ARCHIVED_FILES, resolved) ~= nil then
		return true
	end
	if startsWith(resolved, "docs/reference/") and table.find(PUBLIC_REFERENCE, resolved) == nil then
		return true
	end
	for _, prefix in ARCHIVED_PREFIXES do
		if startsWith(resolved, prefix) then
			return true
		end
	end
	return false
end

local function replacement(label: string, target: string, document: string): string
	local pathOnly = beforeFragment(target)
	local shown = resolve(pathOnly, document)
	local bare = strip(stripBackticks(strip(label)))
	local samePath = bare == target
		or bare == pathOnly
		or bare == basename(pathOnly)
		or bare == shown
		or (string.find(bare, "/", 1, true) ~= nil and resolve(bare, document) == shown)
	if samePath then
		return ("`%s` %s"):format(shown, NOTE)
	end
	return ("%s `%s` %s"):format(label, shown, NOTE)
end

local function documents(repository: string): { string }
	local found: { string } = {}
	for _, directory in SCANNED_DIRS do
		for _, entry in Files.list(Files.join(repository, directory)) do
			if entry.type ~= "file" or string.sub(entry.name, -3) ~= ".md" then
				continue
			end
			local document = directory .. "/" .. entry.name
			if startsWith(document, "docs/reference/") and table.find(PUBLIC_REFERENCE, document) == nil then
				continue
			end
			table.insert(found, document)
		end
	end
	return found
end

type Offender = { line: number, target: string }

local function rewrite(document: string, source: string): (string, { Offender }, number)
	local offenders: { Offender } = {}
	local parts: { string } = {}
	local cursor = 1
	local found = links(source)
	for _, link in found do
		if isArchived(link.target, document) then
			local _, newlines = string.gsub(string.sub(source, 1, link.start - 1), "\n", "")
			table.insert(offenders, { line = newlines + 1, target = link.target })
			table.insert(parts, string.sub(source, cursor, link.start - 1))
			table.insert(parts, replacement(link.label, link.target, document))
			cursor = link.finish + 1
		end
	end
	table.insert(parts, string.sub(source, cursor))
	return table.concat(parts), offenders, #found
end

local function relink(repository: string, mode: "check" | "fix", say: Say): number
	local totalLinks = 0
	local totalOffenders = 0
	local changedFiles = 0
	local scanned = documents(repository)
	for _, document in scanned do
		local path = Files.join(repository, document)
		local raw = Files.read(path)
		local source = string.gsub(string.gsub(raw, "\r\n", "\n"), "\r", "\n")
		local rewritten, offenders, count = rewrite(document, source)
		totalLinks += count
		if #offenders == 0 then
			continue
		end
		totalOffenders += #offenders
		changedFiles += 1
		for _, offender in offenders do
			say(("%s:%d: links into archived material -> %s"):format(document, offender.line, offender.target))
		end
		if mode == "fix" then
			local output = if string.find(raw, "\r\n", 1, true) ~= nil
				then string.gsub(rewritten, "\n", "\r\n")
				else rewritten
			Files.write(path, output)
		end
	end
	if mode == "fix" then
		say(
			("%s: rewrote %d link(s) in %d file(s); %d documents scanned, %d links read"):format(
				RELINK,
				totalOffenders,
				changedFiles,
				#scanned,
				totalLinks
			)
		)
		return 0
	end
	if totalOffenders > 0 then
		say(
			("%s: FAIL — %d link(s) into archived material in %d file(s) of %d scanned"):format(
				RELINK,
				totalOffenders,
				changedFiles,
				#scanned
			)
		)
		return 1
	end
	say(
		("%s: PASS — %d documents, %d links, none pointing into archived material"):format(
			RELINK,
			#scanned,
			totalLinks
		)
	)
	return 0
end

local function collector(): ({ string }, Say)
	local lines: { string } = {}
	return lines, function(line: string)
		table.insert(lines, line)
	end
end

local function withDirectory(body: (root: string) -> string?): string?
	local root = Files.temporaryDirectory("facet-archive-case-")
	local ok, result = pcall(body, root)
	Files.remove(root)
	if not ok then
		return "raised: " .. tostring(result)
	end
	return result
end

local function contains(lines: { string }, fragment: string): boolean
	for _, line in lines do
		if string.find(line, fragment, 1, true) ~= nil then
			return true
		end
	end
	return false
end

local function cases(): { Case.Case }
	return {
		{
			name = "private: archive, verify, re-archive and planted faults",
			run = function(): string?
				return withDirectory(function(work: string): string?
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
					return Case.first(
						Case.equal(code, 0, "archive exit"),
						Case.equal(copied, 3, "copied"),
						Case.equal(clean, 0, "a clean archive verifies"),
						Case.equal(entries, 3, "re-archiving is idempotent"),
						Case.expect(
							string.find(sums, "  docs/one.md\n", 1, true) ~= nil,
							"SHA256SUMS lacks docs/one.md"
						),
						Case.equal(Json.stringField(manifest, "schema"), SCHEMA, "schema"),
						Case.expect(tampered ~= 0, "a planted checksum mismatch verified"),
						Case.expect(contains(lines, "CHECKSUM  vendor/Thing/init.luau"), "no CHECKSUM line"),
						Case.equal(restored, 0, "restored archive"),
						Case.expect(deleted ~= 0, "a deleted archived file verified"),
						Case.expect(absent ~= 0, "archiving a missing path passed"),
						Case.expect(outside ~= 0, "archiving the parent directory passed")
					)
				end)
			end,
		},
		{
			name = "private: SHA256SUMS disagreement and unrecorded files",
			run = function(): string?
				return withDirectory(function(work: string): string?
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
					return Case.first(
						Case.equal(noted, 0, "verify with a stray file"),
						Case.expect(contains(lines, "note: 1 other file(s)"), "no unrecorded note"),
						Case.equal(disagreed, 1, "disagreeing sums"),
						Case.expect(
							contains(lines, "SUMS      a.txt: MANIFEST.json and SHA256SUMS disagree"),
							"no SUMS line"
						),
						Case.equal(missingSums, 1, "missing sums"),
						Case.expect(contains(listed, "          2  "), "list lacks the padded size"),
						Case.expect(contains(listed, "1 file(s) in"), "no list summary")
					)
				end)
			end,
		},
		{
			name = "relink: finds and rewrites links into archived material",
			run = function(): string?
				return withDirectory(function(root: string): string?
					local guide = table.concat({
						"See [the plan](../plans/one.md) and [`docs/adr/0001.md`](../adr/0001.md#why).",
						"Keep [the API](../reference/api.md) and [site](https://example.com/docs/adr/x.md).",
						'A [nested [label] here](/artifacts/run.json "title") and [inventory](../INVENTORY.md).',
						"Private [ref](../reference/internal.md), [anchor](#top), [split",
						"label](../lessons/l.md).",
						"",
					}, "\r\n")
					Files.write(Files.join(root, "docs/guide/one.md"), guide)
					Files.write(Files.join(root, "docs/guide/clean.md"), "[ok](02-architecture.md)\n")
					Files.write(Files.join(root, "docs/reference/internal.md"), "[x](../plans/p.md)\n")
					local lines, say = collector()
					local checked = relink(root, "check", say)
					local fixLines, fixSay = collector()
					local fixed = relink(root, "fix", fixSay)
					local after = Files.read(Files.join(root, "docs/guide/one.md"))
					local expected = table.concat({
						"See the plan `docs/plans/one.md` (archived privately) and `docs/adr/0001.md` (archived privately).",
						"Keep [the API](../reference/api.md) and [site](https://example.com/docs/adr/x.md).",
						"A nested [label] here `artifacts/run.json` (archived privately) and inventory `docs/INVENTORY.md` (archived privately).",
						"Private ref `docs/reference/internal.md` (archived privately), [anchor](#top), split",
						"label `docs/lessons/l.md` (archived privately).",
						"",
					}, "\r\n")
					local passLines, passSay = collector()
					local clean = relink(root, "check", passSay)
					return Case.first(
						Case.equal(checked, 1, "check exit"),
						Case.expect(
							contains(lines, "docs/guide/one.md:1: links into archived material -> ../plans/one.md"),
							"line 1 offender"
						),
						Case.expect(
							contains(lines, "docs/guide/one.md:4: links into archived material -> ../lessons/l.md"),
							"multi-line label offender line"
						),
						Case.expect(
							contains(lines, "FAIL — 6 link(s) into archived material in 1 file(s) of 2 scanned"),
							"check summary"
						),
						Case.equal(fixed, 0, "fix exit"),
						Case.expect(
							contains(fixLines, "rewrote 6 link(s) in 1 file(s); 2 documents scanned, 10 links read"),
							"fix summary"
						),
						Case.equal(after, expected, "rewritten document"),
						Case.equal(clean, 0, "clean after fix"),
						Case.expect(contains(passLines, "PASS — 2 documents, 4 links"), "pass summary")
					)
				end)
			end,
		},
		{
			name = "relink: link grammar edge cases",
			run = function(): string?
				local function targets(source: string): { string }
					local found: { string } = {}
					for _, link in links(source) do
						table.insert(found, link.label .. "=>" .. link.target)
					end
					return found
				end
				return Case.first(
					Case.same(targets('[a](b) [c] (d) [e](f g) [h](i "t")'), { "a=>b", "h=>i" }, "basic"),
					Case.same(targets("[[a](x) [b](y)"), { "a=>x", "b=>y" }, "unclosed outer bracket"),
					Case.same(targets("[a [b [c]] d](z)"), {}, "doubly nested"),
					Case.same(targets("[](empty) [x]()"), { "=>empty" }, "empty label and target"),
					Case.same(targets('[a](b\u{a0}"t")'), { "a=>b" }, "unicode whitespace before a title"),
					Case.equal(strip("\u{3000} `x` \u{a0}"), "`x`", "unicode strip")
				)
			end,
		},
	}
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
		return Case.report("archive", cases)
	end
	local area = invocation.positional[1]
	if area == "private" then
		local unknown = Cli.unknownFlags(invocation, { "root", "source" })
		if unknown ~= nil then
			print(("%s: unrecognized argument %s"):format(PRIVATE, unknown))
			return 2
		end
		return runPrivate(invocation)
	elseif area == "relink" then
		local check = Cli.switch(invocation, "check")
		local fix = Cli.switch(invocation, "fix")
		local unknown = Cli.unknownFlags(invocation, { "check", "fix", "root" })
		if unknown ~= nil or #invocation.positional > 1 or check == fix then
			print(USAGE)
			return 2
		end
		return relink(Cli.flag(invocation, "root") or ".", if fix then "fix" else "check", print)
	end
	print(USAGE)
	return 2
end

local command: Cli.Command = {
	name = "archive",
	summary = "Keep the private archive (private archive|verify|list) and relink archived material.",
	usage = USAGE,
	values = { "root", "source" },
	cases = cases,
	run = run,
}

return command
