--!strict

local net = require("@std/net")
local Case = require("../lib/case")
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Hash = require("../lib/hash")
local Zlib = require("../lib/zlib")
local Tar = require("../lib/tar")
local WordLists = require("../lib/word_lists")

type WordSet = { [string]: boolean }
type Tiers = { [number]: WordSet }
type Lengths = { [number]: WordSet }

type Source = {
	byTier: Tiers,
	solutionByTier: Tiers,
	copyright: string,
	version: string?,
}

type Node =
	{ kind: "map", entries: { { key: string, value: Node } } }
	| { kind: "list", items: { Node } }
	| {
		kind: "text",
		value: string,
	}
	| { kind: "number", value: number }
	| { kind: "none" }

local USAGE = [[usage: lute run tools/facet words [--offline] [--root DIR]
       lute run tools/facet words --check [--root DIR]
       lute run tools/facet words --selftest

Generate the examples' shared English word data from a licensed, versioned source.

    lute run tools/facet words              # generate, verifying the source hash
    lute run tools/facet words --check      # verify the checked-in files, no source needed
    lute run tools/facet words --selftest   # prove each refusal can fire

  --offline   refuse to download; use a cached archive only
  --root DIR  the library root (default: the current directory)

WHY THIS EXISTS. The word game shipped six possible answers and thirty-four
accepted guesses typed into its own source. A player typing an ordinary English
word was told it was not a word, which teaches the wrong lesson about the
example and about the framework. The crossword game needs the same vocabulary at
several lengths. One generated, licensed, provenance-carrying data set serves
both, and nothing is typed by hand.

THE SOURCE IS SCOWL, and it is chosen because it is *designed* to be turned into
redistributable spelling lists: its own Copyright file grants permission to
"use, copy, modify, distribute and sell these word lists, the associated
scripts, the output created from the scripts, and its documentation for any
purpose", provided the notices travel with the copies. Those notices are copied
verbatim into the generated PROVENANCE.md, which is the whole point of doing
this from a real source instead of a scrape.

WHAT IT REFUSES. Every refusal below has a reason it is not merely defensive:

  1. A source archive whose SHA-256 does not match SOURCE_SHA256. "A dictionary"
     is not a provenance claim; a specific archive is. Without the pin, a
     re-download years later silently changes what the game accepts and every
     test that asserts a word is accepted becomes a test about the internet.
  2. A generated file whose recorded hash no longer matches its content
     (`--check`). This is the half that runs with no network and no source
     archive, so a fresh clone, a gate row and the suite can all hold the claim.
     The recorded hashes are of the LF form of each file, so a CRLF checkout
     verifies the same bytes git stores.
  3. An empty or implausibly small output set. A filter bug that produces four
     words is otherwise a perfectly green run: the files regenerate, the hashes
     agree with themselves, and the game rejects the alphabet.
  4. A solution that is not itself an accepted guess. That combination is
     unwinnable and undetectable from either list alone.
  5. A module that would exceed the engine's Source write cap. Studio refuses a
     Source write at 200,000 characters, and the refusal is silent enough that a
     live-synced session then runs the PREVIOUS version of the module while
     every file on disk looks correct.

THE FILTERS ARE POLICY, AND THEY ARE WRITTEN DOWN. SCOWL grades every word by
how widely it is known: size 10 is the most common thousand words, 95 is
everything including the obscure. Two different jobs need two different cuts:

  * accepting a guess should be generous, because a player who types a real word
    and is refused blames the game. Sizes up to 70 give 36,601 words at lengths
    two to seven, and cover every ordinary word tried against it (crane, fjord,
    mocha, ninja, sushi, adieu).
  * choosing an answer should be conservative, because an answer nobody knows is
    not a puzzle. Sizes up to 35 give familiar words, and simple plurals and
    past tenses are dropped on top of that -- "asked" and "cakes" are real words
    and poor answers.]]

local SOURCE_NAME = "SCOWL (Spell Checker Oriented Word Lists) 2020.12.07"
local SOURCE_URL = "https://downloads.sourceforge.net/project/wordlist/SCOWL/2020.12.07/scowl-2020.12.07.tar.gz"
local SOURCE_SHA256 = "5587667caa20c4891390c2d42dbb4d5c4c3f41bee77af1457ece3ba23fb859cc"
local SOURCE_ROOT = "scowl-2020.12.07"
local SOURCE_HOME = "http://wordlist.aspell.net/"

local TIERS = { 10, 20, 35, 40, 50, 55, 60, 70, 80, 95 }

local ACCEPT_DIALECTS = {
	"english",
	"american",
	"british",
	"british_z",
	"canadian",
	"australian",
	"variant_1",
	"variant_2",
	"variant_3",
}
local SOLUTION_DIALECTS = { "english", "american" }

local ACCEPT_MAX_TIER = 70
local ACCEPT_MIN_LEN = 2
local ACCEPT_MAX_LEN = 7

local SOLUTION_MAX_TIER = 35
local SOLUTION_LEN = 6

local MIN_ACCEPTED = {
	{ length = 2, floor = 50 },
	{ length = 3, floor = 400 },
	{ length = 4, floor = 1500 },
	{ length = 5, floor = 3000 },
	{ length = 6, floor = 5000 },
	{ length = 7, floor = 7000 },
}
local MIN_SOLUTIONS = 1000

local SOURCE_CHAR_CAP = 180000
local WORDS_PER_LINE = 400

local OUT_DIR = WordLists.OUT_DIR
local CACHE_DIR = "tools/.wordlist-cache"
local PREFIX = "facet words"

local WHITESPACE = "[\t\n\v\f\r\x1c-\x1f \x85\xa0]"
local LINE = "[^\n\r\v\f\x1c\x1d\x1e\x85]+"
local WORD = "^" .. WHITESPACE .. "*([a-z]+)" .. WHITESPACE .. "*$"

local LUAU_HEADER = "--!strict\n--!nolint LocalShadow\n\n\n-- Source: "
	.. SOURCE_NAME
	.. "\n--   "
	.. SOURCE_URL
	.. "\n--   SHA-256 "
	.. SOURCE_SHA256
	.. "\n-- Licence and required notices: examples/gallery/examples/words/PROVENANCE.md\n"

local PROVENANCE = [=[
# Where these words come from

The two example games — the six-letter word game and the crossword tile game —
share one generated English word set. Nothing here is typed by hand, and nothing
is fetched while a game is running.

## Source

| | |
|---|---|
| Name | {SOURCE_NAME} |
| Project home | {SOURCE_HOME} |
| Archive | `{SOURCE_URL}` |
| Archive SHA-256 | `{SOURCE_SHA256}` |
| `VERSION` inside the archive | `{version}` |

The generator refuses to run against an archive whose SHA-256 does not match the
pinned value, so "a dictionary" is never the provenance claim — a specific,
identified archive is.

## What was taken from it, and why

SCOWL grades every word by how widely it is known: size 10 is roughly the
thousand commonest English words, size 95 is everything including the obscure.
Two jobs want two different cuts.

**Accepted guesses** use sizes 10 through {ACCEPT_MAX_TIER} across **every dialect
SCOWL ships** — {accept_dialects} — restricted to the `-words` classes, which is what
excludes proper names, abbreviations and contractions without a second guess-filter.
Lengths {ACCEPT_MIN_LEN} through {ACCEPT_MAX_LEN} are kept, because the crossword needs
short words and the word game needs six-letter ones.

*Every* dialect, and that is deliberate. With American and pan-English alone, `axe`,
`grey`, `colour`, `theatre`, `centre`, `favour`, `litre`, `cheque`, `kerb`, `tyre` and
`pyjamas` were all refused — SCOWL files those under `british-words` and the
`variant_*` classes. A player who types `grey` and is told it is not a word blames the
game, and is right to.

{counts}

Accepting a guess is deliberately generous: a player who types a real word and is
told it is not one blames the game, and is right to.

**Answers** use sizes 10 through {SOLUTION_MAX_TIER} at {SOLUTION_LEN} letters, from
{solution_dialects} only, minus simple plurals (a word ending in *s* whose {SOLUTION_LEN - 1}-letter
stem is also a word) and simple past tenses. The answer set stays on one spelling
convention on purpose: a puzzle whose answer is `colour` is unfair to half its players
and `color` to the other half, so guesses accept both and answers pick one. That leaves **{len(solutions):,}** familiar words. Choosing an
answer is deliberately conservative: an answer nobody knows is not a puzzle, and
*walked* and *chairs* are real words but poor ones.

Every answer is also an accepted guess. The generator refuses to write the files
if that is ever untrue, because a puzzle whose answer the game would reject
cannot be won and neither list can see the problem on its own.

## Transformations applied

1. Read `final/<dialect>-words.N` for each size N in the chosen range and each
   dialect listed above, decoding as ISO-8859-1 (SCOWL's own encoding). The answer
   set keeps only the American and pan-English half of what that reads.
2. Keep only entries matching `^[a-z]+$` — this drops accented forms and anything
   with an apostrophe, and it is why no capitalisation rule is needed.
3. Keep the length range named above.
4. For answers only, apply the plural and past-tense filters described above.
5. Sort, pack each length into one fixed-width string, and record a SHA-256 per
   generated file in `manifest.luau`.

## Regenerating

```sh
lute run tools/facet words            # generate (downloads the archive once)
lute run tools/facet words --check    # verify the checked-in files; no network
```

`--check` is the half that runs anywhere: it re-hashes the generated files
against `manifest.luau` and needs neither the archive nor a network. The suite
runs the same comparison, so hand-edited word data fails a test rather than
quietly changing what the games accept.

## Required notices

SCOWL's licence grants permission to use, copy, modify, distribute and sell the
word lists and *the output created from the scripts* — provided the notices
travel with the copies. They are reproduced here in full, verbatim from the
archive's own `Copyright` file.

```
{copyright_text.rstrip()}
```
]=]

local function contains(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

local function isWhitespace(byte: number): boolean
	return byte == 32 or (byte >= 9 and byte <= 13) or (byte >= 28 and byte <= 31) or byte == 0x85 or byte == 0xA0
end

local function trimEnd(text: string): string
	local last = #text
	while last > 0 and isWhitespace(string.byte(text, last)) do
		last -= 1
	end
	return string.sub(text, 1, last)
end

local function trim(text: string): string
	local first = 1
	while first <= #text and isWhitespace(string.byte(text, first)) do
		first += 1
	end
	return trimEnd(string.sub(text, first))
end

local function latin1(text: string): string
	local converted = string.gsub(text, "[\x80-\xff]", function(character: string): string
		return utf8.char(string.byte(character))
	end)
	return converted
end

local function grouped(value: number): string
	local digits = string.reverse(("%d"):format(value))
	local separated = string.reverse((string.gsub(digits, "(%d%d%d)", "%1,")))
	if string.sub(separated, 1, 1) == "," then
		return string.sub(separated, 2)
	end
	return separated
end

local function sortedWords(words: WordSet): { string }
	local ordered: { string } = {}
	for word in words do
		table.insert(ordered, word)
	end
	table.sort(ordered)
	return ordered
end

local function sizeOf(words: WordSet?): number
	local count = 0
	if words ~= nil then
		for _ in words do
			count += 1
		end
	end
	return count
end

local function sortedLengths(byLength: Lengths): { number }
	local lengths: { number } = {}
	for length in byLength do
		table.insert(lengths, length)
	end
	table.sort(lengths)
	return lengths
end

local function emptyTiers(): Tiers
	local tiers: Tiers = {}
	for _, tier in TIERS do
		tiers[tier] = {}
	end
	return tiers
end

local function normalizedText(contents: string): string
	local lf = string.gsub(contents, "\r\n", "\n")
	local unified = string.gsub(lf, "\r", "\n")
	return unified
end

local function writeIfChanged(path: string, text: string): boolean
	if Files.isFile(path) and normalizedText(Files.read(path)) == text then
		return false
	end
	Files.write(path, text)
	return true
end

local function fetchSource(root: string, offline: boolean, say: (string) -> ()): (string?, string?)
	local cacheDirectory = Files.join(root, CACHE_DIR)
	Files.makeDirectory(cacheDirectory)
	local path = Files.join(cacheDirectory, Files.name(SOURCE_URL))
	if Files.isFile(path) then
		local cached = Files.read(path)
		local got = Hash.sha256(cached)
		if got == SOURCE_SHA256 then
			return cached, nil
		end
		say(("cached archive hash %s != pinned %s; refetching"):format(got, SOURCE_SHA256))
		Files.remove(path)
	end
	if offline then
		return nil,
			("%s: no verified source archive at %s and --offline was given.\n  Download it once: curl -sSL -o %s %s"):format(
				PREFIX,
				path,
				path,
				SOURCE_URL
			)
	end
	say(("downloading %s"):format(SOURCE_URL))
	local requested, response = pcall(function(): net.Response
		return net.request(SOURCE_URL)
	end)
	if not requested then
		return nil, ("%s: could not download %s: %s"):format(PREFIX, SOURCE_URL, tostring(response))
	end
	local reply = response :: net.Response
	if not reply.ok then
		return nil, ("%s: downloading %s returned HTTP %d"):format(PREFIX, SOURCE_URL, reply.status)
	end
	local got = Hash.sha256(reply.body)
	if got ~= SOURCE_SHA256 then
		return nil,
			table.concat({
				("%s: downloaded archive SHA-256 %s"):format(PREFIX, got),
				("  does not match the pinned %s."):format(SOURCE_SHA256),
				"  Refusing to generate word data from an unidentified source. If the upstream",
				"  release genuinely changed, update SOURCE_SHA256 and SOURCE_NAME together and",
				"  say so in the generated PROVENANCE.md.",
			}, "\n")
	end
	Files.write(path, reply.body)
	return reply.body, nil
end

local function readSource(archive: string): (Source?, string?)
	local inflated, tarball = pcall(function(): string
		return buffer.tostring(Zlib.gunzip(buffer.fromstring(archive)))
	end)
	if not inflated then
		return nil, ("%s: could not decompress the source archive: %s"):format(PREFIX, tostring(tarball))
	end
	local listed, entries = pcall(Tar.read, tarball :: string)
	if not listed then
		return nil, ("%s: could not read the source archive: %s"):format(PREFIX, tostring(entries))
	end
	local byTier = emptyTiers()
	local solutionByTier = emptyTiers()
	local copyright: string? = nil
	local version: string? = nil
	local escapedRoot = string.gsub(SOURCE_ROOT, "%p", "%%%0")
	local member = "^" .. escapedRoot .. "/final/([a-z_0-9]+)%-words%.(%d+)$"
	for _, entry in entries :: { Tar.Entry } do
		if entry.kind ~= "file" then
			continue
		end
		if entry.name == SOURCE_ROOT .. "/Copyright" then
			copyright = entry.data
			continue
		end
		if entry.name == SOURCE_ROOT .. "/VERSION" then
			version = trim(entry.data)
			continue
		end
		local dialect, tierText = string.match(entry.name, member)
		if dialect == nil or tierText == nil then
			continue
		end
		local tier = tonumber(tierText) :: number
		local words = byTier[tier]
		if not contains(ACCEPT_DIALECTS, dialect) or words == nil then
			continue
		end
		local solutionWords = if contains(SOLUTION_DIALECTS, dialect) then solutionByTier[tier] else nil
		for line in string.gmatch(entry.data, LINE) do
			local word = string.match(line, WORD)
			if word ~= nil then
				words[word] = true
				if solutionWords ~= nil then
					solutionWords[word] = true
				end
			end
		end
	end
	if copyright == nil then
		return nil, ("%s: the archive carries no Copyright file — refusing to ship its output"):format(PREFIX)
	end
	return { byTier = byTier, solutionByTier = solutionByTier, copyright = copyright, version = version }, nil
end

local function cumulative(byTier: Tiers, maxTier: number): WordSet
	local union: WordSet = {}
	for _, tier in TIERS do
		if tier > maxTier then
			break
		end
		for word in byTier[tier] do
			union[word] = true
		end
	end
	return union
end

local function buildSets(byTier: Tiers, solutionByTier: Tiers): (Lengths, WordSet)
	local byLength: Lengths = {}
	for word in cumulative(byTier, ACCEPT_MAX_TIER) do
		local length = #word
		if length >= ACCEPT_MIN_LEN and length <= ACCEPT_MAX_LEN then
			local words = byLength[length]
			if words == nil then
				words = {}
				byLength[length] = words
			end
			words[word] = true
		end
	end
	local stem: WordSet = byLength[SOLUTION_LEN - 1] or {}
	local shortStem: WordSet = byLength[SOLUTION_LEN - 2] or {}
	local function isSimplePlural(word: string): boolean
		return string.sub(word, -1) == "s" and stem[string.sub(word, 1, -2)] == true
	end
	local function isSimplePast(word: string): boolean
		return string.sub(word, -2) == "ed"
			and (stem[string.sub(word, 1, -2)] == true or shortStem[string.sub(word, 1, -3)] == true)
	end
	local solutions: WordSet = {}
	for word in cumulative(solutionByTier, SOLUTION_MAX_TIER) do
		if #word == SOLUTION_LEN and not isSimplePlural(word) and not isSimplePast(word) then
			solutions[word] = true
		end
	end
	return byLength, solutions
end

local function checkSets(byLength: Lengths, solutions: WordSet): string?
	for _, minimum in MIN_ACCEPTED do
		local got = sizeOf(byLength[minimum.length])
		if got < minimum.floor then
			return table.concat({
				("%s: only %d accepted words of length %d; the floor is %d."):format(
					PREFIX,
					got,
					minimum.length,
					minimum.floor
				),
				"  A filter that produces almost nothing regenerates cleanly and hashes against itself,",
				"  so the floor is the only thing that can notice.",
			}, "\n")
		end
	end
	local solutionCount = sizeOf(solutions)
	if solutionCount < MIN_SOLUTIONS then
		return ("%s: only %d solutions; the floor is %d."):format(PREFIX, solutionCount, MIN_SOLUTIONS)
	end
	local accepted: WordSet = byLength[SOLUTION_LEN] or {}
	local missing: { string } = {}
	for _, word in sortedWords(solutions) do
		if not accepted[word] then
			table.insert(missing, word)
		end
	end
	if #missing > 0 then
		local shown: { string } = {}
		for index = 1, math.min(5, #missing) do
			table.insert(shown, "'" .. missing[index] .. "'")
		end
		return table.concat({
			("%s: %d solution(s) are not accepted guesses, e.g. [%s]."):format(
				PREFIX,
				#missing,
				table.concat(shown, ", ")
			),
			"  Such a puzzle cannot be won and neither list can see the problem alone.",
		}, "\n")
	end
	return nil
end

local function packedModule(length: number, words: WordSet): (string?, string?)
	local ordered = sortedWords(words)
	local lines: { string } = {}
	for first = 1, #ordered, WORDS_PER_LINE do
		local chunk = table.move(ordered, first, math.min(first + WORDS_PER_LINE - 1, #ordered), 1, {})
		table.insert(lines, '\t"' .. table.concat(chunk) .. '",')
	end
	local body = "\nlocal CHUNKS = {\n"
		.. table.concat(lines, "\n")
		.. "\n}\n\nreturn table.freeze({\n"
		.. ("\tlength = %d,\n"):format(length)
		.. ("\tcount = %d,\n"):format(#ordered)
		.. "\tpacked = table.concat(CHUNKS),\n"
		.. "})\n"
	local text = string.gsub(LUAU_HEADER .. body, "\n\n\n+", "\n\n")
	local characters = utf8.len(text) or #text
	if characters > SOURCE_CHAR_CAP then
		return nil,
			table.concat({
				("%s: the length-%d module would be %d characters, over the"):format(PREFIX, length, characters),
				("  %d cap. Roblox refuses a Source write at 200,000 characters and the"):format(SOURCE_CHAR_CAP),
				"  refusal is quiet: a live-synced session keeps running the previous module while every",
				"  file on disk looks right. Split the length or narrow the tier before shipping this.",
			}, "\n")
	end
	return text, nil
end

local function luaValue(node: Node, indent: string): string
	local childIndent = indent .. "\t"
	if node.kind == "map" then
		local parts: { string } = {}
		for _, entry in node.entries do
			table.insert(parts, ('%s\t["%s"] = %s,\n'):format(indent, entry.key, luaValue(entry.value, childIndent)))
		end
		return "{\n" .. table.concat(parts) .. indent .. "}"
	elseif node.kind == "list" then
		local parts: { string } = {}
		for _, item in node.items do
			table.insert(parts, ("%s\t%s,\n"):format(indent, luaValue(item, childIndent)))
		end
		return "{\n" .. table.concat(parts) .. indent .. "}"
	elseif node.kind == "number" then
		return ("%d"):format(node.value)
	elseif node.kind == "text" then
		local escaped = string.gsub(string.gsub(node.value, "\\", "\\\\"), '"', '\\"')
		return '"' .. escaped .. '"'
	end
	return "nil"
end

local function map(entries: { { key: string, value: Node } }): Node
	return { kind = "map", entries = entries }
end

local function text(value: string?): Node
	if value == nil then
		return { kind = "none" }
	end
	return { kind = "text", value = value }
end

local function number(value: number): Node
	return { kind = "number", value = value }
end

local function texts(values: { string }): Node
	local items: { Node } = {}
	for _, value in values do
		table.insert(items, text(value))
	end
	return { kind = "list", items = items }
end

local function manifestModule(manifest: Node): string
	return "--!strict\n\nreturn table.freeze(" .. luaValue(manifest, "") .. ")\n"
end

local function provenanceMarkdown(copyright: string, version: string?, byLength: Lengths, solutions: WordSet): string
	local acceptDialects: { string } = {}
	for _, dialect in ACCEPT_DIALECTS do
		table.insert(acceptDialects, "`" .. dialect .. "`")
	end
	local solutionDialects: { string } = {}
	for _, dialect in SOLUTION_DIALECTS do
		table.insert(solutionDialects, "`" .. dialect .. "`")
	end
	local counts: { string } = {}
	for _, length in sortedLengths(byLength) do
		table.insert(counts, ("| %d letters | %s |"):format(length, grouped(sizeOf(byLength[length]))))
	end
	local values: { [string]: string } = {
		SOURCE_NAME = SOURCE_NAME,
		SOURCE_HOME = SOURCE_HOME,
		SOURCE_URL = SOURCE_URL,
		SOURCE_SHA256 = SOURCE_SHA256,
		version = version or "None",
		ACCEPT_MAX_TIER = tostring(ACCEPT_MAX_TIER),
		accept_dialects = table.concat(acceptDialects, ", "),
		ACCEPT_MIN_LEN = tostring(ACCEPT_MIN_LEN),
		ACCEPT_MAX_LEN = tostring(ACCEPT_MAX_LEN),
		counts = table.concat(counts, "\n"),
		SOLUTION_MAX_TIER = tostring(SOLUTION_MAX_TIER),
		SOLUTION_LEN = tostring(SOLUTION_LEN),
		solution_dialects = table.concat(solutionDialects, ", "),
		["SOLUTION_LEN - 1"] = tostring(SOLUTION_LEN - 1),
		["len(solutions):,"] = grouped(sizeOf(solutions)),
		["copyright_text.rstrip()"] = latin1(trimEnd(copyright)),
	}
	local filled = string.gsub(PROVENANCE, "{([^{}\n]+)}", function(key: string): string
		local value = values[key]
		if value == nil then
			error("the provenance template names an unknown value: " .. key, 0)
		end
		return value
	end)
	return filled
end

type Written = { name: string, text: string }

local function generate(root: string, offline: boolean): number
	local archive, fetchFailure = fetchSource(root, offline, print)
	if archive == nil then
		print(fetchFailure or (PREFIX .. ": no source archive"))
		return 1
	end
	local source, readFailure = readSource(archive)
	if source == nil then
		print(readFailure or (PREFIX .. ": the source archive could not be read"))
		return 1
	end
	local byLength, solutions = buildSets(source.byTier, source.solutionByTier)
	local refusal = checkSets(byLength, solutions)
	if refusal ~= nil then
		print(refusal)
		return 1
	end
	local directory = Files.join(root, OUT_DIR)
	Files.makeDirectory(directory)
	local written: { Written } = {}
	local function emit(name: string, length: number, words: WordSet): boolean
		local moduleText, failure = packedModule(length, words)
		if moduleText == nil then
			print(failure or (PREFIX .. ": the module could not be packed"))
			return false
		end
		writeIfChanged(Files.join(directory, name), moduleText)
		table.insert(written, { name = name, text = moduleText })
		return true
	end
	for _, length in sortedLengths(byLength) do
		if not emit(("len%d.luau"):format(length), length, byLength[length]) then
			return 1
		end
	end
	if not emit("solutions.luau", SOLUTION_LEN, solutions) then
		return 1
	end
	writeIfChanged(
		Files.join(directory, "PROVENANCE.md"),
		provenanceMarkdown(source.copyright, source.version, byLength, solutions)
	)
	table.sort(written, function(left: Written, right: Written): boolean
		return left.name < right.name
	end)
	local countEntries: { { key: string, value: Node } } = {}
	local summary: { string } = {}
	for _, length in sortedLengths(byLength) do
		local size = sizeOf(byLength[length])
		table.insert(countEntries, { key = tostring(length), value = number(size) })
		table.insert(summary, ("len%d=%d"):format(length, size))
	end
	local fileEntries: { { key: string, value: Node } } = {}
	for _, file in written do
		table.insert(fileEntries, { key = file.name, value = text(WordLists.hashText(file.text)) })
	end
	local manifest = map({
		{ key = "schema", value = text("facet-word-data/1") },
		{
			key = "source",
			value = map({
				{ key = "name", value = text(SOURCE_NAME) },
				{ key = "url", value = text(SOURCE_URL) },
				{ key = "sha256", value = text(SOURCE_SHA256) },
				{ key = "version", value = text(source.version) },
				{ key = "home", value = text(SOURCE_HOME) },
			}),
		},
		{
			key = "policy",
			value = map({
				{ key = "acceptedMaxTier", value = number(ACCEPT_MAX_TIER) },
				{
					key = "acceptedLengths",
					value = { kind = "list", items = { number(ACCEPT_MIN_LEN), number(ACCEPT_MAX_LEN) } },
				},
				{ key = "solutionMaxTier", value = number(SOLUTION_MAX_TIER) },
				{ key = "solutionLength", value = number(SOLUTION_LEN) },
				{ key = "acceptDialects", value = texts(ACCEPT_DIALECTS) },
				{ key = "solutionDialects", value = texts(SOLUTION_DIALECTS) },
				{ key = "droppedFromSolutions", value = texts({ "simple plurals", "simple past tenses" }) },
			}),
		},
		{ key = "counts", value = map(countEntries) },
		{ key = "solutionCount", value = number(sizeOf(solutions)) },
		{ key = "files", value = map(fileEntries) },
	})
	writeIfChanged(Files.join(directory, WordLists.MANIFEST), manifestModule(manifest))
	table.insert(summary, ("solutions=%d"):format(sizeOf(solutions)))
	print("word data: " .. table.concat(summary, ", "))
	print(("wrote %d files under %s/"):format(#written + 2, OUT_DIR))
	return 0
end

local function check(root: string): number
	local verification = WordLists.verify(root)
	local refusal = verification.refusal
	if refusal ~= nil then
		print(("%s --check: %s"):format(PREFIX, refusal))
		return 1
	end
	if #verification.mismatches > 0 then
		local lines = { ("%s --check: generated word data does not match its manifest:"):format(PREFIX) }
		for _, mismatch in verification.mismatches do
			table.insert(lines, ("  %s: %s"):format(mismatch.name, mismatch.problem))
		end
		table.insert(lines, "  Regenerate with: " .. WordLists.REGENERATE)
		print(table.concat(lines, "\n"))
		return 1
	end
	print(("word data: %d generated files match %s"):format(verification.recorded, WordLists.MANIFEST))
	return 0
end

local function run(invocation: Cli.Invocation): number
	local unknown = Cli.unknownFlags(invocation, { "check", "offline", "root" })
	if unknown ~= nil or #invocation.positional > 0 then
		print(
			("%s: unexpected argument %s. Run `lute run tools/facet words --help`."):format(
				PREFIX,
				unknown or invocation.positional[1]
			)
		)
		return 2
	end
	local root = Cli.flag(invocation, "root") or "."
	if Cli.switch(invocation, "check") then
		return check(root)
	end
	return generate(root, Cli.switch(invocation, "offline"))
end

local function digits(index: number, width: number): string
	return ("%0" .. width .. "d"):format(index)
end

local function numbered(length: number, count: number): WordSet
	local words: WordSet = {}
	for index = 0, count - 1 do
		words[digits(index, length)] = true
	end
	return words
end

local function setOf(words: { string }): WordSet
	local set: WordSet = {}
	for _, word in words do
		set[word] = true
	end
	return set
end

local function floorsMet(): Lengths
	local byLength: Lengths = {}
	for _, minimum in MIN_ACCEPTED do
		byLength[minimum.length] = numbered(minimum.length, minimum.floor + 1)
	end
	return byLength
end

local function octalField(value: number, width: number): string
	return ("%0" .. (width - 1) .. "o"):format(value) .. "\0"
end

local function tarFile(name: string, data: string): string
	local function padded(value: string, width: number): string
		return value .. string.rep("\0", width - #value)
	end
	local header = padded(name, 100)
		.. octalField(420, 8)
		.. octalField(0, 8)
		.. octalField(0, 8)
		.. octalField(#data, 12)
		.. octalField(0, 12)
		.. "        "
		.. "0"
		.. string.rep("\0", 100)
		.. "ustar\0"
		.. "00"
		.. string.rep("\0", 247)
	header = padded(header, 512)
	local sum = 0
	for index = 1, 512 do
		sum += string.byte(header, index)
	end
	header = string.sub(header, 1, 148) .. ("%06o"):format(sum) .. "\0 " .. string.sub(header, 157)
	return header .. data .. string.rep("\0", (512 - #data % 512) % 512)
end

local function archiveOf(files: { { name: string, data: string } }): string
	local parts: { string } = {}
	for _, file in files do
		table.insert(parts, tarFile(file.name, file.data))
	end
	table.insert(parts, string.rep("\0", 1024))
	local tarball = table.concat(parts)
	return buffer.tostring(Zlib.gzip(buffer.fromstring(tarball), { stored = true }))
end

local function refusal(failure: string?, fragment: string): string?
	if failure == nil then
		return ("the refusal containing '%s' did not fire"):format(fragment)
	end
	if string.find(failure, fragment, 1, true) == nil then
		return ("expected a refusal containing '%s', got '%s'"):format(fragment, failure)
	end
	return nil
end

local function cases(): { Case.Case }
	local list: { Case.Case } = {
		{
			name = "the per-length floor fires on a one-word set",
			run = function(): string?
				return refusal(checkSets({ [5] = setOf({ "aaaaa" }) }, setOf({ "aaaaa" })), "accepted words of length")
			end,
		},
		{
			name = "the solution floor fires",
			run = function(): string?
				return refusal(checkSets(floorsMet(), setOf({ "zzzzz" })), "solutions; the floor is")
			end,
		},
		{
			name = "the solution-is-an-accepted-guess rule fires",
			run = function(): string?
				local byLength = floorsMet()
				byLength[SOLUTION_LEN] = numbered(SOLUTION_LEN, MIN_ACCEPTED[SOLUTION_LEN - 1].floor + 1)
				local solutions = numbered(SOLUTION_LEN, MIN_SOLUTIONS)
				solutions.zzzzzz = true
				return Case.first(
					refusal(checkSets(byLength, solutions), "1 solution(s) are not accepted guesses, e.g. ['zzzzzz']"),
					Case.equal(checkSets(byLength, numbered(SOLUTION_LEN, MIN_SOLUTIONS)), nil, "accepted solutions")
				)
			end,
		},
		{
			name = "the Source character cap fires",
			run = function(): string?
				local _, failure = packedModule(7, numbered(7, 40000))
				return refusal(failure, "over the\n  180000 cap")
			end,
		},
		{
			name = "a packed module has the generated layout",
			run = function(): string?
				local moduleText = packedModule(2, setOf({ "of", "an", "to" }))
				local expected = LUAU_HEADER:gsub("\n\n\n", "\n\n")
					.. '\nlocal CHUNKS = {\n\t"anofto",\n}\n\nreturn table.freeze({\n'
					.. "\tlength = 2,\n\tcount = 3,\n\tpacked = table.concat(CHUNKS),\n})\n"
				return Case.equal(moduleText, expected, "module")
			end,
		},
		{
			name = "a manifest module is written in insertion order",
			run = function(): string?
				local moduleText = manifestModule(map({
					{ key = "schema", value = text('a "quoted" \\ value') },
					{ key = "version", value = text(nil) },
					{ key = "lengths", value = { kind = "list", items = { number(2), number(7) } } },
				}))
				local expected = '--!strict\n\nreturn table.freeze({\n\t["schema"] = "a \\"quoted\\" \\\\ value",\n'
					.. '\t["version"] = nil,\n\t["lengths"] = {\n\t\t2,\n\t\t7,\n\t},\n})\n'
				return Case.equal(moduleText, expected, "manifest")
			end,
		},
		{
			name = "counts are grouped by thousands",
			run = function(): string?
				return Case.first(
					Case.equal(grouped(94), "94"),
					Case.equal(grouped(3258), "3,258"),
					Case.equal(grouped(1234567), "1,234,567")
				)
			end,
		},
		{
			name = "an archive without a Copyright file is refused",
			run = function(): string?
				local _, failure = readSource(archiveOf({
					{ name = SOURCE_ROOT .. "/final/english-words.10", data = "cat\n" },
				}))
				return refusal(failure, "carries no Copyright file")
			end,
		},
		{
			name = "the source reader keeps the listed dialects, tiers and plain words",
			run = function(): string?
				local source, failure = readSource(archiveOf({
					{ name = SOURCE_ROOT .. "/Copyright", data = "Copyright \xa9 Kevin\n\xa0\n" },
					{ name = SOURCE_ROOT .. "/VERSION", data = " 2020.12.07\n" },
					{ name = SOURCE_ROOT .. "/final/english-words.10", data = "cat\r\n dog \nCaps\ncan't\ncaf\xe9\n" },
					{ name = SOURCE_ROOT .. "/final/british-words.20", data = "colour\x85grey\xa0\n" },
					{ name = SOURCE_ROOT .. "/final/english-words.15", data = "untiered\n" },
					{ name = SOURCE_ROOT .. "/final/english-proper-names.10", data = "london\n" },
					{ name = SOURCE_ROOT .. "/final/special-words.10", data = "special\n" },
				}))
				if source == nil then
					return failure or "the reader refused a valid archive"
				end
				return Case.first(
					Case.same(sortedWords(source.byTier[10]), { "cat", "dog" }, "tier 10"),
					Case.same(sortedWords(source.byTier[20]), { "colour", "grey" }, "tier 20"),
					Case.same(sortedWords(source.solutionByTier[10]), { "cat", "dog" }, "solutions at tier 10"),
					Case.same(sortedWords(source.solutionByTier[20]), {}, "solutions at tier 20"),
					Case.equal(source.version, "2020.12.07", "version"),
					Case.equal(latin1(trimEnd(source.copyright)), "Copyright \u{a9} Kevin", "copyright")
				)
			end,
		},
		{
			name = "a cached archive with the wrong hash is removed and --offline refuses",
			run = function(): string?
				local root = Files.temporaryDirectory("facet-words-")
				local cached = Files.join(root, CACHE_DIR, Files.name(SOURCE_URL))
				Files.write(cached, "not the pinned archive")
				local said: { string } = {}
				local archive, failure = fetchSource(root, true, function(line: string)
					table.insert(said, line)
				end)
				local removed = not Files.exists(cached)
				Files.remove(root)
				return Case.first(
					Case.equal(archive, nil, "archive"),
					refusal(failure, "--offline was given"),
					Case.expect(removed, "the mismatched cache was kept"),
					refusal(said[1], "refetching")
				)
			end,
		},
		{
			name = "an unchanged file is not rewritten across line endings",
			run = function(): string?
				local root = Files.temporaryDirectory("facet-words-")
				local path = Files.join(root, "same.luau")
				Files.write(path, "--!strict\r\nreturn {}\r\n")
				local rewrote = writeIfChanged(path, "--!strict\nreturn {}\n")
				local kept = Files.read(path)
				local changed = writeIfChanged(path, "--!strict\nreturn { 1 }\n")
				local after = Files.read(path)
				Files.remove(root)
				return Case.first(
					Case.equal(rewrote, false, "rewrote"),
					Case.equal(kept, "--!strict\r\nreturn {}\r\n", "kept"),
					Case.equal(changed, true, "changed"),
					Case.equal(after, "--!strict\nreturn { 1 }\n", "after")
				)
			end,
		},
	}
	for _, case in WordLists.cases() do
		table.insert(list, case)
	end
	return list
end

local command: Cli.Command = {
	name = "words",
	summary = "Generate the example word data from the pinned SCOWL archive, or --check it.",
	usage = USAGE,
	values = { "root" },
	cases = cases,
	run = run,
}

return command
