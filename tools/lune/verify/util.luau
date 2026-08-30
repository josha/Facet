--!strict
--[[ Shared primitives for the verification graph (distribution-readiness D7).

	Deliberately tiny and dependency-free: canonical JSON (so a hash over a
	record does not depend on Lua's table iteration order), glob matching, a
	file walk, and sha256. Everything else in tools/lune/verify/ builds on these.

	CANONICAL JSON IS NOT A PRETTY-PRINTER. It exists so that `bodyHash` means
	something: two runs that produced the same record must hash the same, and a
	record edited by hand must not. `serde.encode` iterates a Luau table in hash
	order, which differs between processes, so it cannot be used for either. ]]

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local util = {}

function util.sha256(text: string): string
	return serde.hash("sha256", text)
end

-- LF-normalised file content. A CRLF checkout and an LF one describe the same
-- source, and an identity that disagreed about that would rerun everything on a
-- machine whose git happened to be configured differently.
function util.readNormalized(path: string): string
	local text = fs.readFile(path)
	text = string.gsub(text, "\r\n", "\n")
	return text
end

--[[ MEMOISED, BECAUSE THE TREE DOES NOT MOVE DURING A RUN.

	133 producers, most of them declaring the same generous source globs, means
	the same few thousand files are walked and hashed once per producer if
	nothing caches. Measured on the first run of the coordinator: minutes of pure
	Luau, with no child process alive to explain it.

	Caching within one process is also what makes identities COHERENT: every
	producer in a run is keyed against the same snapshot of the tree, so a
	sibling agent's edit landing mid-run cannot give two producers two different
	ideas of what the source was. ]]
local hashCache: { [string]: string } = {}

function util.fileHash(path: string): string
	local cached = hashCache[path]
	if cached ~= nil then
		return cached
	end
	local ok, text = pcall(util.readNormalized, path)
	local hash = if ok then util.sha256(text :: string) else "<vanished>"
	hashCache[path] = hash
	return hash
end

-- ---- canonical JSON ---------------------------------------------------------

local encodeValue

local function encodeString(s: string): string
	local out = string.gsub(s, '[%c"\\]', function(c: string): string
		if c == '"' then
			return '\\"'
		elseif c == "\\" then
			return "\\\\"
		elseif c == "\n" then
			return "\\n"
		elseif c == "\r" then
			return "\\r"
		elseif c == "\t" then
			return "\\t"
		end
		return string.format("\\u%04x", string.byte(c))
	end)
	return '"' .. out .. '"'
end

local function isArray(t: { [any]: any }): boolean
	local n = 0
	for _ in t do
		n += 1
	end
	return n == #t
end

encodeValue = function(value: any): string
	local t = type(value)
	if value == nil then
		return "null"
	elseif t == "boolean" then
		return tostring(value)
	elseif t == "number" then
		-- integers print without a decimal point so a count never depends on
		-- how a float happened to round on the way through
		if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
			return string.format("%d", value)
		end
		--[[ A FRACTION MUST PARSE BACK TO ITSELF, or this encoder is not
			canonical and every body hash over a record holding one is a coin
			toss. `%.17g` is enough digits — but `%g` STRIPS TRAILING ZEROS, so a
			double whose 17-digit form ends in 0 prints as 16 digits, and 16 is
			not always enough to name a double uniquely. Measured 2026-08-30 on a
			per-case timing of 90.477916644886150: it printed 90.47791664488615,
			parsed back as a DIFFERENT double, re-encoded as 90.477916644886164,
			and the suite's stored result — the single most expensive producer in
			the graph — was refused on every run as "edited after it was
			written". Widen until it round-trips. ]]
		return string.format("%.18g", value)
	elseif t == "string" then
		return encodeString(value)
	elseif t == "table" then
		if isArray(value) then
			local parts: { string } = {}
			for _, v in value do
				table.insert(parts, encodeValue(v))
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys: { string } = {}
		for k in value do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts: { string } = {}
		for _, k in keys do
			table.insert(parts, encodeString(k) .. ":" .. encodeValue(value[k]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	error(`canonicalJson: unsupported value of type {t}`)
end

function util.canonicalJson(value: any): string
	return encodeValue(value)
end

-- ---- globs ------------------------------------------------------------------

local MAGIC = "[%^%$%(%)%%%.%[%]%*%+%-%?]"

--[[ `src/**` matches every path under src/; `tools/lune/*.luau` matches one
	segment; `?` matches one character that is not a separator. Translated to a
	Lua pattern rather than matched by hand so the whole rule is one line of
	code a reader can check. ]]
local patternCache: { [string]: string } = {}

function util.globToPattern(glob: string): string
	local cached = patternCache[glob]
	if cached ~= nil then
		return cached
	end
	local out: { string } = { "^" }
	local i = 1
	while i <= #glob do
		if string.sub(glob, i, i + 2) == "**/" then
			table.insert(out, ".-")
			i += 3
		elseif string.sub(glob, i, i + 1) == "**" then
			table.insert(out, ".-")
			i += 2
		elseif string.sub(glob, i, i) == "*" then
			table.insert(out, "[^/]-")
			i += 1
		elseif string.sub(glob, i, i) == "?" then
			table.insert(out, "[^/]")
			i += 1
		else
			local c = string.sub(glob, i, i)
			if string.match(c, MAGIC) then
				table.insert(out, "%" .. c)
			else
				table.insert(out, c)
			end
			i += 1
		end
	end
	table.insert(out, "$")
	local pattern = table.concat(out)
	patternCache[glob] = pattern
	return pattern
end

function util.matchesAny(path: string, globs: { string }): boolean
	for _, g in globs do
		if string.match(path, util.globToPattern(g)) ~= nil then
			return true
		end
	end
	return false
end

-- ---- file walk --------------------------------------------------------------

local SKIP_DIRS = {
	[".git"] = true,
	["build"] = true,
	["__pycache__"] = true,
	["node_modules"] = true,
}

local function walkInto(root: string, prefix: string, out: { string })
	local ok, entries = pcall(fs.readDir, root)
	if not ok then
		return
	end
	table.sort(entries :: { string })
	for _, name in entries :: { string } do
		if SKIP_DIRS[name] then
			continue
		end
		local full = `{root}/{name}`
		local rel = if prefix == "" then name else `{prefix}/{name}`
		if fs.isDir(full) then
			walkInto(full, rel, out)
		elseif fs.isFile(full) then
			table.insert(out, rel)
		end
	end
end

local walkCache: { [string]: { string } } = {}

-- Every file under `root`, as paths relative to the repository root, sorted.
function util.walk(root: string): { string }
	local cached = walkCache[root]
	if cached ~= nil then
		return cached
	end
	local out: { string } = {}
	if fs.isFile(root) then
		table.insert(out, root)
		walkCache[root] = out
		return out
	end
	if not fs.isDir(root) then
		walkCache[root] = out
		return out
	end
	walkInto(root, root, out)
	table.sort(out)
	walkCache[root] = out
	return out
end

-- The roots a set of globs could possibly touch, so a walk does not have to
-- read the whole repository to answer a question about `docs/**`.
--[[ Drop the per-run snapshot. A coordinator run never needs this — the point
	of the caches is that every producer in one run is keyed against the same
	tree — but the selftest edits a file and then asks a SECOND run's question,
	and a test that could not do that could not prove the identity moves. ]]
function util.resetCaches()
	table.clear(hashCache)
	table.clear(walkCache)
end

function util.globRoots(globs: { string }): { string }
	local seen: { [string]: boolean } = {}
	local roots: { string } = {}
	for _, g in globs do
		local head = string.match(g, "^([^*?]*)/") or g
		head = string.gsub(head, "/+$", "")
		if head == "" then
			head = "."
		end
		if not seen[head] then
			seen[head] = true
			table.insert(roots, head)
		end
	end
	table.sort(roots)
	return roots
end

return util
