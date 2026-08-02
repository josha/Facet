--!strict
-- Shared artifact writer for LuauUI tool commands: ensures the directory
-- exists (Dropbox drops empty dirs) and writes pretty JSON.

local fs = require("@lune/fs")
local serde = require("@lune/serde")

local artifact = {}

function artifact.writeJson(path: string, value: any)
	local dir = string.match(path, "^(.*)/[^/]+$")
	if dir ~= nil and dir ~= "" and not fs.isDir(dir) then
		fs.writeDir(dir)
	end
	fs.writeFile(path, serde.encode("json", value, true))
end

return artifact
