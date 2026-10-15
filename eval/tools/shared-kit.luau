--!strict

local process = require("@std/process")

local Files = require("../../tools/facet/lib/files")
local Hash = require("../../tools/facet/lib/hash")
local Json = require("../../tools/facet/lib/json")

local USAGE = [[usage: lute run eval/tools/shared-kit.luau [--out DIR]

Writes the generated files that both arms share into DIR (default
artifacts/facetbench/arm-shared): the pinned Roblox definitions that
tools/typecheck/check.luau reads, from the cache that lute run tools/facet types
writes.]]

local LOCK = "tools/typecheck/roblox.lock.json"
local CACHE = "artifacts/verify/types/roblox.d.luau"

local function main(): number
	local out = "artifacts/facetbench/arm-shared"
	local index = 2
	while index <= #process.args do
		local word = process.args[index]
		if word == "--out" and process.args[index + 1] ~= nil then
			out = process.args[index + 1]
			index += 1
		else
			print(USAGE)
			return 2
		end
		index += 1
	end
	local digest = Json.stringField(Json.decode(Files.read(LOCK)), "sha256")
	if not Files.isFile(CACHE) or Hash.sha256(Files.read(CACHE)) ~= digest then
		print("shared-kit: the Roblox definitions are not cached; run lute run tools/facet types once")
		return 1
	end
	Files.copy(CACHE, Files.join(out, "tools/typecheck/roblox.d.luau"))
	Files.copy(LOCK, Files.join(out, "tools/typecheck/roblox.lock.json"))
	print(("shared-kit: wrote the Roblox definitions into %s"):format(out))
	return 0
end

process.exit(main())
