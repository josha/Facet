--!strict

local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")

export type Kind = "file" | "directory" | "link" | "other" | "missing"

export type WalkOptions = {
	skip: { [string]: boolean }?,
	directories: boolean?,
	prune: ((relative: string) -> boolean)?,
}

local Files = {}

local sequence = 0

function Files.normalize(value: string): string
	local slashed = string.gsub(value, "\\", "/")
	return slashed
end

function Files.join(...: string): string
	local parts: { string } = {}
	for _, part in { ... } do
		if part ~= "" and part ~= "." then
			table.insert(parts, Files.normalize(part))
		end
	end
	if #parts == 0 then
		return "."
	end
	local joined = table.concat(parts, "/")
	local collapsed = string.gsub(joined, "/+", "/")
	return collapsed
end

function Files.parent(value: string): string
	local normalized = Files.normalize(value)
	local directory = string.match(normalized, "^(.*)/[^/]*$")
	if directory == nil then
		return "."
	end
	if directory == "" then
		return "/"
	end
	return directory
end

function Files.name(value: string): string
	local normalized = Files.normalize(value)
	return string.match(normalized, "([^/]*)$") or normalized
end

function Files.stem(value: string): string
	local name = Files.name(value)
	return string.match(name, "^(.+)%.[^.]*$") or name
end

function Files.extension(value: string): string
	local name = Files.name(value)
	return string.match(name, "^.+(%.[^.]*)$") or ""
end

function Files.kind(value: string): Kind
	local ok, kind = pcall(fs.type, value)
	if not ok then
		return "missing"
	end
	if kind == "file" then
		return "file"
	elseif kind == "dir" then
		return "directory"
	elseif kind == "link" then
		return "link"
	end
	return "other"
end

function Files.exists(value: string): boolean
	return fs.exists(value)
end

function Files.isFile(value: string): boolean
	return Files.kind(value) == "file"
end

function Files.isDirectory(value: string): boolean
	return Files.kind(value) == "directory"
end

function Files.read(value: string): string
	return fs.readFileToString(value)
end

function Files.text(value: string): string
	local contents = fs.readFileToString(value)
	local normalized = string.gsub(contents, "\r\n", "\n")
	return normalized
end

function Files.lines(contents: string): { string }
	local normalized = string.gsub(contents, "\r\n", "\n")
	local lines = string.split(normalized, "\n")
	if lines[#lines] == "" then
		table.remove(lines)
	end
	return lines
end

function Files.makeDirectory(value: string)
	local normalized = Files.normalize(value)
	if normalized == "" or normalized == "." or Files.isDirectory(normalized) then
		return
	end
	local parent = Files.parent(normalized)
	if parent ~= normalized and parent ~= "." and parent ~= "/" and not string.match(parent, "^%a:$") then
		Files.makeDirectory(parent)
	end
	if not Files.isDirectory(normalized) then
		fs.createDirectory(normalized)
	end
end

function Files.write(value: string, contents: string)
	Files.makeDirectory(Files.parent(value))
	fs.writeStringToFile(value, contents)
end

function Files.writeAtomic(value: string, contents: string)
	sequence += 1
	local temporary = ("%s.tmp.%d.%d"):format(value, process.pid(), sequence)
	Files.write(temporary, contents)
	if Files.exists(value) then
		fs.remove(value)
	end
	fs.move(temporary, value)
end

function Files.remove(value: string)
	local kind = Files.kind(value)
	if kind == "directory" then
		fs.removeDirectory(value, { recursive = true })
	elseif kind ~= "missing" then
		fs.remove(value)
	end
end

function Files.copy(source: string, destination: string)
	Files.makeDirectory(Files.parent(destination))
	fs.copy(source, destination)
end

function Files.move(source: string, destination: string)
	Files.makeDirectory(Files.parent(destination))
	if Files.exists(destination) then
		Files.remove(destination)
	end
	fs.move(source, destination)
end

function Files.copyTree(source: string, destination: string)
	Files.makeDirectory(destination)
	for _, relative in Files.walk(source) do
		Files.copy(Files.join(source, relative), Files.join(destination, relative))
	end
end

function Files.list(value: string): { fs.DirectoryEntry }
	if not Files.isDirectory(value) then
		return {}
	end
	local entries = fs.listDirectory(value)
	table.sort(entries, function(left: fs.DirectoryEntry, right: fs.DirectoryEntry): boolean
		return left.name < right.name
	end)
	return entries
end

function Files.walk(root: string, options: WalkOptions?): { string }
	local found: { string } = {}
	local skip: { [string]: boolean } = if options and options.skip then options.skip else {}
	local directories = options ~= nil and options.directories == true
	local prune: ((string) -> boolean)? = if options then options.prune else nil
	local function visit(directory: string, prefix: string)
		for _, entry in Files.list(directory) do
			local relative = if prefix == "" then entry.name else prefix .. "/" .. entry.name
			local absolute = directory .. "/" .. entry.name
			local kind = entry.type
			if kind == "link" then
				local resolved = Files.kind(absolute)
				kind = if resolved == "directory" then "dir" elseif resolved == "file" then "file" else "link"
			end
			if kind == "dir" then
				local pruned = false
				local predicate = prune
				if predicate ~= nil then
					pruned = predicate(relative)
				end
				if not skip[entry.name] and not pruned then
					if directories then
						table.insert(found, relative)
					end
					visit(absolute, relative)
				end
			elseif not directories then
				table.insert(found, relative)
			end
		end
	end
	if Files.isDirectory(root) then
		visit(Files.normalize(root), "")
	end
	table.sort(found)
	return found
end

function Files.relative(target: string, base: string): string
	local normalizedTarget = Files.normalize(target)
	local normalizedBase = Files.normalize(base)
	if normalizedBase == "." or normalizedBase == "" then
		return normalizedTarget
	end
	local prefix = if string.sub(normalizedBase, -1) == "/" then normalizedBase else normalizedBase .. "/"
	if string.sub(normalizedTarget, 1, #prefix) == prefix then
		return string.sub(normalizedTarget, #prefix + 1)
	end
	return normalizedTarget
end

function Files.within(target: string, base: string): boolean
	local normalizedTarget = Files.normalize(target)
	local normalizedBase = Files.normalize(base)
	return normalizedTarget == normalizedBase
		or string.sub(normalizedTarget, 1, #normalizedBase + 1) == normalizedBase .. "/"
end

function Files.vendored(relative: string): boolean
	return table.find(string.split(relative, "/"), "vendor") ~= nil
end

function Files.collapse(value: string): string
	local normalized = Files.normalize(value)
	local absolute = string.sub(normalized, 1, 1) == "/"
	local drive = string.match(normalized, "^(%a:)/") or string.match(normalized, "^(%a:)$")
	local body = if drive
		then string.sub(normalized, #drive + 2)
		elseif absolute then string.sub(normalized, 2)
		else normalized
	local parts: { string } = {}
	for _, part in string.split(body, "/") do
		if part == "" or part == "." then
			continue
		elseif part == ".." and #parts > 0 and parts[#parts] ~= ".." then
			table.remove(parts)
		elseif part == ".." and (absolute or drive) then
			continue
		else
			table.insert(parts, part)
		end
	end
	local joined = table.concat(parts, "/")
	if drive then
		return drive .. "/" .. joined
	elseif absolute then
		return "/" .. joined
	end
	return if joined == "" then "." else joined
end

function Files.absolute(value: string): string
	local normalized = Files.normalize(value)
	if string.sub(normalized, 1, 1) == "/" or string.match(normalized, "^%a:/") then
		return Files.collapse(normalized)
	end
	return Files.collapse(Files.cwd() .. "/" .. normalized)
end

function Files.cwd(): string
	return Files.normalize(path.format(process.cwd()))
end

function Files.temporaryDirectory(prefix: string): string
	sequence += 1
	local base = Files.normalize(path.format(system.tmpdir()))
	for attempt = 1, 100 do
		local candidate = ("%s/%s%d-%d-%d"):format(base, prefix, process.pid(), sequence, attempt + math.random(1, 1e6))
		if not Files.exists(candidate) then
			Files.makeDirectory(candidate)
			return candidate
		end
	end
	error("could not create a temporary directory under " .. base)
end

function Files.modifiedSeconds(value: string): number
	return fs.metadata(value).modified:toSeconds()
end

function Files.size(value: string): number
	return fs.metadata(value).size
end

return table.freeze(Files)
