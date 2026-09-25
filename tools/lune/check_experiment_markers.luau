--!strict
local fs = require("@lune/fs")

local checker = {}

local ROOT = "src"

export type Violation = {
	file: string,
	line: number,
	token: string,
	text: string,
}

export type Options = {
	root: string?,
	injectFile: string?,
	injectLine: string?,
}

export type Result = {
	ok: boolean,
	violations: { Violation },
	counts: { files: number, lines: number },
}

local function luauFilesUnder(dir: string, out: { string })
	for _, entry in fs.readDir(dir) do
		local path = `{dir}/{entry}`
		if fs.isDir(path) then
			luauFilesUnder(path, out)
		elseif string.sub(entry, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

local function markersIn(line: string, out: { string })
	for token in string.gmatch(line, "%f[%w_]ZZ[%w_]*") do
		table.insert(out, token)
	end
end

function checker.files(root: string?): { string }
	local files: { string } = {}
	luauFilesUnder(root or ROOT, files)
	table.sort(files)
	return files
end

function checker.check(opts: Options?): Result
	local options: Options = opts or {}
	local files = checker.files(options.root)
	local violations: { Violation } = {}
	local lineCount = 0
	for _, file in files do
		local source = fs.readFile(file)
		if options.injectFile == file and options.injectLine ~= nil then
			source ..= "\n" .. (options.injectLine :: string) .. "\n"
		end
		local n = 0
		for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
			n += 1
			lineCount += 1
			local tokens: { string } = {}
			markersIn(line, tokens)
			for _, token in tokens do
				table.insert(violations, {
					file = file,
					line = n,
					token = token,
					text = (string.gsub(line, "^%s+", "")),
				})
			end
		end
	end
	return {
		ok = #violations == 0,
		violations = violations,
		counts = { files = #files, lines = lineCount },
	}
end

function checker.describe(v: Violation): string
	return `{v.file}:{v.line}: '{v.token}' is a scratch experiment marker. Remove it from src/. `
		.. `Put scratch work in tests/, bench/ or tools/. A shipped flag needs a real name and a documented default.`
end

return checker
