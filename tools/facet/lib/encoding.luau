--!strict

local Files = require("./files")

local Encoding = {}

function Encoding.normalize(paths: { string }): { string }
	local changed: { string } = {}
	local seen: { [string]: boolean } = {}
	local function normalize(file: string)
		if seen[file] or (Files.extension(file) ~= ".luau" and Files.extension(file) ~= ".lua") then
			return
		end
		seen[file] = true
		local source = Files.read(file)
		if string.sub(source, 1, 3) == "\239\187\191" then
			Files.write(file, string.sub(source, 4))
			table.insert(changed, file)
		end
	end
	for _, path in paths do
		if Files.isFile(path) then
			normalize(path)
		else
			for _, relative in Files.walk(path, { skip = { vendor = true, [".git"] = true } }) do
				normalize(Files.join(path, relative))
			end
		end
	end
	return changed
end

return table.freeze(Encoding)
