--!strict

local net = require("@std/net")
local Files = require("./files")
local Hash = require("./hash")
local Json = require("./json")

local Definitions = {}

local function fail(message: string): never
	error(message, 0)
end

function Definitions.resolve(lockFile: string, file: string): string
	local lock = Json.decode(Files.read(lockFile))
	local digest = Json.stringField(lock, "sha256") or fail(lockFile .. " has no sha256")
	local url = Json.stringField(lock, "url") or fail(lockFile .. " has no url")

	if Files.isFile(file) and Hash.sha256(Files.read(file)) == digest then
		return file
	end
	local fetched, response = pcall(function(): net.Response
		return net.request(url)
	end)
	if not fetched then
		fail(("could not download the Roblox definitions from %s: %s"):format(url, tostring(response)))
	end
	local answer = response :: net.Response
	if not answer.ok then
		fail(("could not download the Roblox definitions from %s: HTTP %d"):format(url, answer.status))
	end
	if Hash.sha256(answer.body) ~= digest then
		fail("Roblox definitions differ from their pinned SHA-256")
	end
	Files.write(file, answer.body)
	return file
end

return Definitions
