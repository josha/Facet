--!strict

local Files = require("./files")
local Run = require("./run")

local Inputs = {}
local MEASURED = { "src/", "bench/", "examples/", "tests/", "tools/", "eval/" }
local DOCUMENTS = { "docs/", "skills/" }
local NOTICES = { LICENSE = true }
local RETAINED_ENTRIES = { "tools/engine/retained_memory_proof.luau", "bench/paired_scene.luau" }
local RETAINED_SUBJECT = { "src/", "examples/" }
local RETAINED_FILES = { "pkg.luau", "pkg.lock.luau", ".luaurc", "rokit.toml" }

local function startsWith(path: string, prefixes: { string }): boolean
	for _, prefix in prefixes do
		if string.sub(path, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

function Inputs.affects(path: string): boolean
	if path == ".github/workflows/ci.yml" or startsWith(path, MEASURED) then
		return true
	end
	if NOTICES[path] or startsWith(path, DOCUMENTS) then
		return false
	end
	return string.lower(string.sub(path, -3)) ~= ".md"
end

local function resolve(root: string, from: string, target: string): string?
	local path: string
	if string.sub(target, 1, 6) == "@repo/" then
		path = string.sub(target, 7)
	elseif string.sub(target, 1, 1) == "." then
		path = Files.join(Files.parent(from), target)
	elseif string.sub(target, 1, 1) ~= "@" and string.sub(target, -5) == ".luau" then
		path = target
	else
		return nil
	end
	path = Files.collapse(path)
	for _, candidate in { path, path .. ".luau", Files.join(path, "init.luau") } do
		if Files.isFile(Files.join(root, candidate)) then
			return candidate
		end
	end
	return nil
end

function Inputs.retainedSources(root: string): { string }
	local seen: { [string]: boolean } = {}
	local pending = table.clone(RETAINED_ENTRIES)
	local sources: { string } = table.clone(RETAINED_FILES)
	while #pending > 0 do
		local path = table.remove(pending) :: string
		if not seen[path] and not startsWith(path, RETAINED_SUBJECT) and Files.isFile(Files.join(root, path)) then
			seen[path] = true
			table.insert(sources, path)
			for target in string.gmatch(Files.read(Files.join(root, path)), 'require%s*%(%s*"([^"]+)"%s*%)') do
				local resolved = resolve(root, path, target)
				if resolved ~= nil then
					table.insert(pending, resolved)
				end
			end
		end
	end
	table.sort(sources)
	return sources
end

function Inputs.select(changed: { string }, retained: { string }?): { string }
	local selected: { string } = {}
	for _, path in changed do
		if if retained ~= nil then table.find(retained, path) ~= nil else Inputs.affects(path) then
			table.insert(selected, path)
		end
	end
	return selected
end

function Inputs.run(base: string?, retained: boolean?): number
	if base == nil or base == "" then
		print("perf affected: a base commit is required")
		return 2
	end
	local result = Run.capture({ "git", "diff", "--name-only", "--no-renames", "-z", base, "HEAD", "--" })
	if not result.ok then
		print(result.stderr)
		return 2
	end
	local paths: { string } = {}
	for path in string.gmatch(result.stdout, "[^%z]+") do
		table.insert(paths, path)
	end
	local subject = if retained then "retained heap proof" else "paired performance"
	local changed = Inputs.select(paths, if retained then Inputs.retainedSources(".") else nil)
	if #changed == 0 then
		print(`perf affected: no {subject} inputs changed`)
		return 3
	end
	print(`perf affected: {#changed} {subject} input(s) changed`)
	for _, path in changed do
		print("  " .. path)
	end
	return 0
end

return table.freeze(Inputs)
