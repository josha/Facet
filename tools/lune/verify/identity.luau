--!strict
--[[ PRODUCER IDENTITY (distribution-readiness D7).

	A producer's identity is the answer to one question: "would running this
	again, right now, be able to say anything different?" If the answer is no,
	the stored result stands; if it is yes — or if we cannot tell — it runs.

	identity = sha256 over, in this order and with every part length-prefixed so
	no two parts can be confused for one another:

	  1. the producer id;
	  2. its exact command and options;
	  3. its environment class;
	  4. the toolchain pins (rokit.toml content, lune/stylua/python versions);
	  5. every file matching its declared `inputs` globs, as
	     `<relative path>\0<sha256 of the LF-normalised content>`, sorted by path;
	  6. its declared fixture inputs, the same way (a missing fixture hashes as
	     the literal string `<absent>`, which is a different identity from any
	     content — so deleting a fixture invalidates rather than being ignored).

	WHY CONTENT AND NEVER TIME. tools/test.sh's header records the rule this
	inherits: a clock- or session-keyed cache that outlives an edit is the
	"reads two checked-in files and executes nothing" shape prior_gates.sh was
	built to remove. Every part of this key is content or a pin.

	WHY OVER-BROAD INPUTS ARE THE SAFE DIRECTION. Several scanners read more of
	the tree than their name suggests, and the binding plan says to default to
	rerun when dependency ownership is uncertain. A scanner costs 0.03-6 s, so an
	unnecessary rerun costs seconds; a missed one costs a wrong green. The
	declarations in graph.luau are therefore generous on purpose. ]]

local fs = require("@lune/fs")
local process = require("@lune/process")

local util = require("./util")

local identity = {}

export type Toolchain = {
	rokit: string,
	lune: string,
	stylua: string,
	python: string,
}

local function firstLine(text: string?): string
	if text == nil then
		return "unavailable"
	end
	local line = string.match(text, "^[^\n]*") or ""
	return (string.gsub(line, "%s+$", ""))
end

local cachedToolchain: Toolchain? = nil

-- The pins, read once per process. `lune --version` and friends are cheap but
-- they are three processes, and identity is computed once per producer.
function identity.toolchain(): Toolchain
	if cachedToolchain ~= nil then
		return cachedToolchain :: Toolchain
	end
	local rokit = if fs.isFile("rokit.toml") then util.sha256(util.readNormalized("rokit.toml")) else "absent"
	local function version(program: string, args: { string }): string
		local ok, result = pcall(process.exec, program, args)
		if not ok or not (result :: any).ok then
			return "unavailable"
		end
		local out = (result :: any).stdout
		if out == nil or out == "" then
			out = (result :: any).stderr
		end
		return firstLine(out)
	end
	local tc: Toolchain = {
		rokit = rokit,
		lune = version("lune", { "--version" }),
		stylua = version("stylua", { "--version" }),
		python = version("python3", { "--version" }),
	}
	cachedToolchain = tc
	return tc
end

function identity.toolchainString(tc: Toolchain): string
	return `rokit={tc.rokit};lune={tc.lune};stylua={tc.stylua};python={tc.python}`
end

--[[ Every file a producer declares, with its content hash. Returned as a sorted
	list of `path\0hash` so the caller can both hash it and, on a miss, say WHICH
	file moved. ]]
function identity.inputDigest(globs: { string }): { string }
	local seen: { [string]: boolean } = {}
	local files: { string } = {}
	for _, root in util.globRoots(globs) do
		for _, rel in util.walk(root) do
			if not seen[rel] and util.matchesAny(rel, globs) then
				seen[rel] = true
				table.insert(files, rel)
			end
		end
	end
	table.sort(files)
	local out: { string } = {}
	for _, rel in files do
		local ok, text = pcall(util.readNormalized, rel)
		-- A file listed by the walk and gone by the time it is read is a sibling
		-- agent's temp file. Hash it as absent: the identity then differs from
		-- the settled tree, which is a MISS and a rerun — slow, never wrong.
		table.insert(out, `{rel}\0{if ok then util.sha256(text :: string) else "<vanished>"}`)
	end
	return out
end

local function fixtureDigest(paths: { string }): { string }
	local sorted = table.clone(paths)
	table.sort(sorted)
	local out: { string } = {}
	for _, p in sorted do
		local ok, text = pcall(util.readNormalized, p)
		table.insert(out, `{p}\0{if ok then util.sha256(text :: string) else "<absent>"}`)
	end
	return out
end

export type Producer = {
	id: string,
	command: string,
	inputs: { string },
	fixtures: { string }?,
	environmentClass: string,
	tiers: { [string]: boolean },
	serialize: boolean?,
	timeoutS: number?,
	note: string?,
	declaredEvidence: string?,
}

export type Identity = {
	hash: string,
	inputCount: number,
	toolchain: string,
}

local function part(label: string, value: string): string
	return `{label}:{#value}:{value}\n`
end

function identity.compute(producer: Producer, tc: Toolchain): Identity
	local inputs = identity.inputDigest(producer.inputs)
	local fixtures = fixtureDigest(producer.fixtures or {})
	local tcString = identity.toolchainString(tc)
	local body = table.concat({
		part("id", producer.id),
		part("command", producer.command),
		part("class", producer.environmentClass),
		part("toolchain", tcString),
		part("inputs", table.concat(inputs, "\n")),
		part("fixtures", table.concat(fixtures, "\n")),
	})
	return {
		hash = util.sha256(body),
		inputCount = #inputs,
		toolchain = tcString,
	}
end

return identity
