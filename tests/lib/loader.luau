--!strict
local Lute = require("../../tools/vendor/verify/src/lute")
local fs = require("@std/fs")

local requireHost = (require :: unknown) :: (string) -> unknown
local ROOTS: { [string]: boolean } = { src = true, examples = true, tests = true, bench = true, tools = true }
local sources: { [string]: string }? = nil

local function sourceFiles(): { [string]: string }
	if sources then
		return sources
	end
	local loaded: { [string]: string } = {}
	for root in ROOTS do
		if fs.exists(root) then
			for _, path in
				Lute.corpus.discover({
					listDir = fs.listDirectory,
					rules = { { root = root, pattern = "%.luau$" } },
				})
			do
				local hosted = string.sub(path, 1, 13) == "tools/vendor/" or string.sub(path, 1, 12) == "tools/facet/"
				loaded[path] = if hosted then "" else fs.readFileToString(path)
			end
		end
	end
	sources = loaded
	return loaded
end

local function new(preload: string?): Lute.Loader
	local files = sourceFiles()
	if preload ~= nil then
		files = table.clone(files)
		for _, path in
			Lute.corpus.discover({
				listDir = fs.listDirectory,
				rules = { { root = preload, pattern = "%.luau$" } },
			})
		do
			files[path] = fs.readFileToString(path)
		end
	end
	return Lute.loader.new({
		files = {
			exists = function(path: string): boolean
				local root = string.gsub(string.match(path, "^[^/]+") or path, "%.luau$", "")
				if files[path] ~= nil then
					return true
				end
				local cached = preload ~= nil and string.sub(path, 1, #preload + 1) == preload .. "/"
				return not ROOTS[root] and not cached and fs.exists(path)
			end,
			readFile = function(path: string): string
				return files[path] or fs.readFileToString(path)
			end,
		},
		aliases = { repo = "" },
		hostPaths = { "tools/vendor/", "tools/facet/" },
		requireHost = function(module: string): unknown
			return requireHost("../../" .. module)
		end,
	})
end

return { new = new }
