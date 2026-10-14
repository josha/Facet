--!strict

local Files = require("./files")
local Hash = require("./hash")
local Json = require("./json")
local Run = require("./run")

export type Project = string | Json.Object

export type Options = {
	cwd: string?,
	scratch: string?,
	quiet: boolean?,
}

export type Outcome = {
	ok: boolean,
	code: number,
	message: string,
}

local Rojo = {}

local sequence = 0

function Rojo.token(): string
	sequence += 1
	return `{os.time()}-{math.random(1, 1e9)}-{sequence}`
end

function Rojo.isAbsolute(value: string): boolean
	local normalized = Files.normalize(value)
	return string.sub(normalized, 1, 1) == "/" or string.match(normalized, "^%a:/") ~= nil
end

function Rojo.locate(base: string, value: string): string
	if Rojo.isAbsolute(value) then
		return Files.normalize(value)
	end
	return Files.join(base, value)
end

function Rojo.success(message: string): Outcome
	return { ok = true, code = 0, message = message }
end

function Rojo.failure(message: string, code: number?): Outcome
	return { ok = false, code = code or 1, message = message }
end

function Rojo.run(argv: { string }, options: Options?): Outcome
	local cwd = if options then options.cwd else nil
	local quiet = options ~= nil and options.quiet == true
	local result = if quiet then Run.capture(argv, { cwd = cwd }) else Run.inherit(argv, { cwd = cwd })
	local message = if quiet then result.stdout .. result.stderr else result.stderr
	if result.ok then
		return Rojo.success(message)
	end
	return Rojo.failure(message, if result.code == 0 then 1 else result.code)
end

local function scratchPath(scratch: string): string
	local token = Rojo.token()
	local base = string.match(scratch, "^(.*)%.project%.json$")
	if base ~= nil then
		return `{base}.{token}.project.json`
	end
	return `{scratch}.{token}`
end

function Rojo.build(project: Project, output: string, options: Options?): Outcome
	local base = if options and options.cwd then options.cwd else "."
	Files.makeDirectory(Files.parent(Rojo.locate(base, output)))
	if type(project) == "string" then
		return Rojo.run({ "rojo", "build", project, "-o", output }, options)
	end
	local scratch = if options then options.scratch else nil
	if scratch == nil then
		return Rojo.failure("a generated project needs a scratch path")
	end
	local relative = scratchPath(scratch)
	local written = Rojo.locate(base, relative)
	Files.write(written, Json.pretty(project))
	local ran, outcome = pcall(Rojo.run, { "rojo", "build", relative, "-o", output }, options)
	Files.remove(written)
	if not ran then
		return Rojo.failure(tostring(outcome))
	end
	return outcome
end

function Rojo.contentFiles(root: string, roots: { string }): { string }
	local found: { string } = {}
	for _, entry in roots do
		local normalized = Files.normalize(entry)
		local location = Files.join(root, normalized)
		if Files.isDirectory(location) then
			for _, relative in Files.walk(location) do
				table.insert(found, normalized .. "/" .. relative)
			end
		elseif Files.isFile(location) then
			table.insert(found, normalized)
		end
	end
	table.sort(found)
	return found
end

function Rojo.contentHash(root: string, roots: { string }, length: number): string
	local lines: { string } = {}
	for _, relative in Rojo.contentFiles(root, roots) do
		table.insert(lines, `{Hash.sha256(Files.read(Files.join(root, relative)))}  {relative}`)
	end
	return string.sub(Hash.sha256(table.concat(lines, "\n") .. "\n"), 1, length)
end

return table.freeze(Rojo)
