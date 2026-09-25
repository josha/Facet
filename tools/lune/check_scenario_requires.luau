--!strict

local fs = require("@lune/fs")
local studio_tree = require("./lib/studio_tree")

local checker = {}

export type Violation = {
	file: string,
	scriptPath: string,
	require: string,
	reason: string,
}

export type Options = {

	injectFile: string?,
	injectLine: string?,
}

local function resolveRelative(scriptPath: string, reqPath: string): (string?, string?)
	local segs: { string } = {}
	for seg in string.gmatch(scriptPath, "[^%.]+") do
		table.insert(segs, seg)
	end
	table.remove(segs)

	for tok in string.gmatch(reqPath, "[^/]+") do
		if tok == "." then
		elseif tok == ".." then
			if #segs == 0 then
				return nil, `could not get parent of component ".."`
			end
			table.remove(segs)
		else
			table.insert(segs, tok)
		end
	end
	return table.concat(segs, "."), nil
end

function checker.check(
	opts: Options?
): { ok: boolean, violations: { Violation }, counts: { files: number, requiresChecked: number } }
	local options = opts or {}
	local entries = studio_tree.entries("gallery")

	local existing: { [string]: boolean } = {}
	for _, e in entries do
		existing[e.path] = true
	end

	local violations: { Violation } = {}
	local filesChecked = 0
	local requiresChecked = 0

	for _, e in entries do
		local isSrc = e.path == "ReplicatedStorage.Facet" or string.match(e.path, "^ReplicatedStorage%.Facet%.") ~= nil
		if e.file == "" or isSrc then
			continue
		end
		filesChecked += 1
		local source = fs.readFile(e.file)
		if options.injectFile == e.file and options.injectLine ~= nil then
			source ..= "\n" .. options.injectLine .. "\n"
		end
		for line in string.gmatch(source .. "\n", "([^\n]*)\n") do
			if string.match(line, "^%s") ~= nil or line == "" then
				continue
			end
			local reqPath = string.match(line, "require%([\"'](%.[^\"']*)[\"']%)")
			if reqPath == nil then
				continue
			end
			requiresChecked += 1
			local resolved, err = resolveRelative(e.path, reqPath)
			if resolved == nil then
				table.insert(violations, {
					file = e.file,
					scriptPath = e.path,
					require = reqPath,
					reason = err :: string,
				})
			elseif not existing[resolved] then
				table.insert(violations, {
					file = e.file,
					scriptPath = e.path,
					require = reqPath,
					reason = `resolves to '{resolved}', which does not exist in the Studio instance tree`,
				})
			end
		end
	end

	return {
		ok = #violations == 0,
		violations = violations,
		counts = { files = filesChecked, requiresChecked = requiresChecked },
	}
end

return checker
