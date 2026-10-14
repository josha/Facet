--!strict
local fs = require("@std/fs")
local Lute = require("../../tools/vendor/verify/src/lute")
local VerifyRoblox = require("../../tools/vendor/verify/src/roblox")

export type Environment = { [string]: unknown }
export type Loader = {
	require: (path: string) -> unknown,
	environment: (value: unknown) -> Environment?,
}

local requireNative = (require :: unknown) :: (string) -> unknown

local NATIVE_PREFIXES = { "tools/vendor/", "tools/facet/" }

local function parent(path: string): string
	return string.match(path, "^(.*)/[^/]*$") or ""
end

local function normalize(path: string): string
	local parts: { string } = {}
	for part in string.gmatch(path, "[^/]+") do
		if part == ".." then
			assert(#parts > 0, "a module path leaves the repository: " .. path)
			table.remove(parts)
		elseif part ~= "." then
			table.insert(parts, part)
		end
	end
	return table.concat(parts, "/")
end

local resolved: { [string]: string } = {}

local function locate(module: string): string
	if string.sub(module, -5) == ".luau" then
		if fs.exists(module) then
			return module
		end
		error("no module at " .. module, 0)
	end
	if fs.exists(module .. ".luau") then
		return module .. ".luau"
	end
	local index = module .. "/init.luau"
	if fs.exists(index) then
		return index
	end
	error("no module at " .. module, 0)
end

local function file(module: string): string
	local known = resolved[module]
	if known == nil then
		known = locate(module)
		resolved[module] = known
	end
	return known
end

local function native(path: string): boolean
	for _, prefix in NATIVE_PREFIXES do
		if string.sub(path, 1, #prefix) == prefix then
			return true
		end
	end
	return false
end

local function warn(...: unknown)
	local parts: { string } = {}
	for index = 1, select("#", ...) do
		table.insert(parts, tostring((select(index, ...))))
	end
	print("[warn] " .. table.concat(parts, " "))
end

local function new(): Loader
	local loaded: { [string]: unknown } = {}
	local loading: { [string]: boolean } = {}
	local environments = (setmetatable({}, { __mode = "k" }) :: unknown) :: { [unknown]: Environment }
	local base = (
		setmetatable({
			warn = warn,
			typeof = VerifyRoblox.datatypes.typeof,
		}, { __index = _G }) :: unknown
	) :: Environment

	local function import(path: string): unknown
		local cached = loaded[path]
		if cached ~= nil or loading[path] then
			assert(not loading[path], "a module requires itself through a cycle: " .. path)
			return cached
		end
		if native(path) then
			local module = if string.sub(path, -10) == "/init.luau" then parent(path) else string.sub(path, 1, -6)
			local value = requireNative("../../" .. module)
			loaded[path] = value
			return value
		end
		local self = if string.sub(path, -10) == "/init.luau" then parent(path) else string.sub(path, 1, -6)
		local directory = parent(self)
		local environment = (setmetatable({}, { __index = base }) :: unknown) :: Environment
		environment.require = function(request: string): unknown
			if string.sub(request, 1, 5) == "@std/" or string.sub(request, 1, 6) == "@lute/" then
				return requireNative(request)
			elseif string.sub(request, 1, 6) == "@self/" then
				return import(file(normalize(self .. "/" .. string.sub(request, 7))))
			elseif string.sub(request, 1, 6) == "@repo/" then
				return import(file(normalize(string.sub(request, 7))))
			end
			assert(
				string.sub(request, 1, 2) == "./" or string.sub(request, 1, 3) == "../",
				`{path} requires an unsupported path: {request}`
			)
			return import(file(normalize(directory .. "/" .. request)))
		end
		environment.getfenv = function(target: unknown): Environment
			if type(target) == "function" then
				return environments[target] or environment
			end
			return environment
		end
		loading[path] = true
		local ok, value = pcall(function(): unknown
			return Lute.chunk.load(
				fs.readFileToString(path),
				{ name = "./" .. path, environment = environment, injectGlobals = false }
			)()
		end)
		loading[path] = nil
		if not ok then
			error(value, 0)
		end
		if type(value) == "function" then
			environments[value] = environment
		end
		loaded[path] = value
		return value
	end

	return {
		require = function(path: string): unknown
			return import(file(normalize(path)))
		end,
		environment = function(value: unknown): Environment?
			return environments[value]
		end,
	}
end

return { new = new }
