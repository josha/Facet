--!strict

local fs = require("@std/fs")
local path = require("@std/path")
local process = require("@std/process")
local system = require("@std/system")

local USAGE = [[usage: lute run tools/typecheck/check.luau [paths...] [--project FILE] [--definitions FILE]
                                                 [--workspace DIR] [--scores FILE]

Type-checks the Luau files in strict mode with luau-lsp, the Roblox definitions
and a Rojo sourcemap of the project. Each file must start with --!strict. It
prints each error and exits 1 when there is an error.

  paths               Files or directories to check. The default is src/client.
  --project FILE      The Rojo project. The default is default.project.json.
  --definitions FILE  The Roblox definitions. The default is
                      tools/typecheck/roblox.d.luau.
  --workspace DIR     Check the project in DIR. The default is the current
                      directory.
  --scores FILE       Also write { passed, errors, files } as JSON to FILE.]]

type Options = {
	paths: { string },
	project: string,
	definitions: string,
	workspace: string,
	scores: string?,
}

local function normalize(value: string): string
	local slashed = string.gsub(value, "\\", "/")
	if string.sub(slashed, 1, 4) == "//?/" then
		slashed = string.sub(slashed, 5)
	end
	return slashed
end

local function absolute(value: string, base: string): string
	local normal = normalize(value)
	if string.match(normal, "^%a:/") ~= nil or string.sub(normal, 1, 1) == "/" then
		return normal
	end
	return base .. "/" .. normal
end

local function parse(args: { string }): Options?
	local options: Options = {
		paths = {},
		project = "default.project.json",
		definitions = "tools/typecheck/roblox.d.luau",
		workspace = normalize(path.format(process.cwd())),
		scores = nil,
	}
	local index = 2
	while index <= #args do
		local word = args[index]
		local value = args[index + 1]
		if word == "--project" and value ~= nil then
			options.project = value
			index += 1
		elseif word == "--definitions" and value ~= nil then
			options.definitions = absolute(value, normalize(path.format(process.cwd())))
			index += 1
		elseif word == "--workspace" and value ~= nil then
			options.workspace = absolute(value, normalize(path.format(process.cwd())))
			index += 1
		elseif word == "--scores" and value ~= nil then
			options.scores = absolute(value, normalize(path.format(process.cwd())))
			index += 1
		elseif string.sub(word, 1, 2) == "--" then
			return nil
		else
			table.insert(options.paths, word)
		end
		index += 1
	end
	if #options.paths == 0 then
		options.paths = { "src/client" }
	end
	return options
end

local function collect(root: string, relative: string, into: { string })
	local full = root .. "/" .. relative
	if not fs.exists(full) then
		return
	end
	if fs.type(full) == "file" then
		if string.match(relative, "%.luau?$") ~= nil then
			table.insert(into, relative)
		end
		return
	end
	for _, entry in fs.listDirectory(full) do
		collect(root, relative .. "/" .. entry.name, into)
	end
end

local function main(): number
	local options = parse(process.args)
	if options == nil then
		print(USAGE)
		return 2
	end
	local chosen = options :: Options
	local root = chosen.workspace
	local files: { string } = {}
	for _, given in chosen.paths do
		collect(root, normalize(given), files)
	end
	table.sort(files)
	local errors: { string } = {}
	for _, file in files do
		local text = string.gsub(fs.readFileToString(root .. "/" .. file), "\r\n", "\n")
		if string.find(text, "^%-%-!strict\n") == nil then
			table.insert(errors, ("%s:1:1: error: the file does not start with --!strict"):format(file))
		end
	end
	local definitions = absolute(chosen.definitions, root)
	if not fs.exists(definitions) then
		table.insert(errors, "error: the Roblox definitions are missing at " .. definitions)
	elseif #files > 0 then
		local scratch = normalize(path.format(system.tmpdir())) .. ("/typecheck-%d-%d"):format(process.pid(), os.time())
		fs.createDirectory(scratch)
		local sourcemap = scratch .. "/sourcemap.json"
		local built = process.run(
			{ "rojo", "sourcemap", chosen.project, "--absolute", "-o", sourcemap },
			{ cwd = root, timeout = 120 }
		)
		if not built.ok then
			table.insert(errors, "error: rojo sourcemap failed: " .. built.stderr)
		else
			local mapped = string.gsub(string.gsub(fs.readFileToString(sourcemap), "\\\\\\\\%?\\\\", ""), "//%?/", "")
			fs.writeStringToFile(sourcemap, mapped)
			local argv = {
				"luau-lsp",
				"analyze",
				"--platform",
				"roblox",
				"--definitions=" .. definitions,
				"--sourcemap=" .. sourcemap,
				"--flag:LuauSolverV2=true",
				"--flag:LuauTarjanChildLimit=100000",
			}
			for _, given in chosen.paths do
				table.insert(argv, given)
			end
			local analyzed = process.run(argv, { cwd = root, timeout = 600 })
			local output = string.gsub(analyzed.stdout .. "\n" .. analyzed.stderr, "\r\n", "\n")
			for _, line in string.split(output, "\n") do
				local start, _, row, column, message = string.find(line, "%((%d+),(%d+)%): %a+Error: (.*)$")
				if start ~= nil and row ~= nil and column ~= nil and message ~= nil then
					local reported =
						string.lower(normalize(string.match(string.sub(line, 1, start - 1), "^(.-%.luau?)") or ""))
					for _, file in files do
						local wanted = string.lower(file)
						if reported == wanted or string.sub(reported, -#wanted - 1) == "/" .. wanted then
							local entry = ("%s:%s:%s: error: %s"):format(file, row, column, message)
							if table.find(errors, entry) == nil then
								table.insert(errors, entry)
							end
							break
						end
					end
				end
			end
		end
		pcall(fs.removeDirectory, scratch, { recursive = true })
	end
	for _, line in errors do
		print(line)
	end
	print(("typecheck: %d file(s), %d error(s)"):format(#files, #errors))
	if chosen.scores ~= nil then
		fs.writeStringToFile(
			chosen.scores :: string,
			('{"passed": %d, "errors": %d, "files": %d}\n'):format(if #errors == 0 then 1 else 0, #errors, #files)
		)
	end
	return if #errors == 0 then 0 else 1
end

process.exit(main())
