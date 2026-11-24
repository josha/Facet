--!strict

local Files = require("./files")
local luau = require("@std/luau")
local path = require("@std/path")
local process = require("@std/process")

export type Locked = {
	alias: string,
	key: string,
	rev: string,
	source: string,
	directory: string,
	store: string?,
}

local Packages = {}

local LOCKFILE = "pkg.lock.luau"
local VENDOR = ".lpm"
local STORE_PREFIX = "@pkg/"

function Packages.encode(key: string): string
	local encoded = string.gsub(key, "[^%w%-_%.@]", function(character: string): string
		return string.format("%%%02X", string.byte(character))
	end)
	return encoded
end

local function field(value: unknown, key: string): unknown
	if type(value) ~= "table" then
		return nil
	end
	return (value :: { [string]: unknown })[key]
end

local function text(value: unknown): string?
	return if type(value) == "string" then value else nil
end

local function storePath(installPath: string?): string?
	if installPath == nil or string.sub(installPath, 1, #STORE_PREFIX) ~= STORE_PREFIX then
		return nil
	end
	local relative = string.gsub(string.sub(installPath, #STORE_PREFIX + 1), "/%.$", "")
	return Files.join(path.format(process.homedir()), ".loom", "store", relative)
end

function Packages.fromLock(document: unknown, alias: string): (Locked?, string?)
	local key = text(field(field(document, "dependencies"), alias))
		or text(field(field(document, "devDependencies"), alias))
	if key == nil then
		return nil, ("%s does not pin %s"):format(LOCKFILE, alias)
	end
	local entry = field(field(document, "packages"), key)
	local rev = text(field(entry, "rev"))
	local source = text(field(entry, "source"))
	if rev == nil or source == nil then
		return nil, ("%s records no source and revision for %s"):format(LOCKFILE, key)
	end
	return {
		alias = alias,
		key = key,
		rev = rev,
		source = source,
		directory = Files.join(VENDOR, Packages.encode(key)),
		store = storePath(text(field(entry, "installPath"))),
	},
		nil
end

function Packages.locked(root: string, alias: string): (Locked?, string?)
	local lockPath = Files.join(root, LOCKFILE)
	if not Files.isFile(lockPath) then
		return nil, ("%s is missing; run lute pkg install --vendor"):format(LOCKFILE)
	end
	local loaded, document = pcall(function(): unknown
		return luau.loadModule(lockPath)
	end)
	if not loaded then
		return nil, ("%s does not load: %s"):format(LOCKFILE, tostring(document))
	end
	return Packages.fromLock(document, alias)
end

function Packages.directory(root: string, alias: string): string
	local locked, problem = Packages.locked(root, alias)
	if locked == nil then
		error(problem or ("%s is not locked"):format(alias), 0)
	end
	local absolute = Files.join(root, locked.directory)
	if not Files.isDirectory(absolute) then
		error(("%s is not installed at %s; run lute pkg install --vendor"):format(alias, locked.directory), 0)
	end
	return locked.directory
end

function Packages.verify(root: string): string
	return Packages.directory(root, "verify")
end

return table.freeze(Packages)
