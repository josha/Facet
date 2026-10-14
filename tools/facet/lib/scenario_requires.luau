--!strict

local StudioTree = require("./studio_tree")

export type FileSystem = StudioTree.FileSystem

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

export type Counts = { files: number, requiresChecked: number }

export type Result = {
	ok: boolean,
	violations: { Violation },
	counts: Counts,
}

export type Checker = {
	check: (options: Options?) -> Result,
}

local ScenarioRequires = {}

local LIBRARY = "ReplicatedStorage.Facet"

local function resolveRelative(scriptPath: string, requested: string): (string?, string?)
	local segments: { string } = {}
	for segment in string.gmatch(scriptPath, "[^%.]+") do
		table.insert(segments, segment)
	end
	table.remove(segments)
	for token in string.gmatch(requested, "[^/]+") do
		if token == ".." then
			if #segments == 0 then
				return nil, 'could not get parent of component ".."'
			end
			table.remove(segments)
		elseif token ~= "." then
			table.insert(segments, token)
		end
	end
	return table.concat(segments, "."), nil
end

function ScenarioRequires.describe(violation: Violation): string
	if violation.require == "" then
		return ("%s (%s): %s"):format(violation.file, violation.scriptPath, violation.reason)
	end
	return ('%s (%s): require("%s") \u{2014} %s'):format(
		violation.file,
		violation.scriptPath,
		violation.require,
		violation.reason
	)
end

function ScenarioRequires.check(fs: FileSystem, root: string?, options: Options?): Result
	local settings: Options = options or {}
	local entries = StudioTree.entries(fs, root, "gallery")
	local existing: { [string]: boolean } = {}
	for _, entry in entries do
		existing[entry.path] = true
	end
	local violations: { Violation } = {}
	local counts: Counts = { files = 0, requiresChecked = 0 }
	for _, entry in entries do
		local library = entry.path == LIBRARY or string.sub(entry.path, 1, #LIBRARY + 1) == LIBRARY .. "."
		if entry.file == "" or library then
			continue
		end
		local located = StudioTree.located(root, entry.file)
		if not fs.isFile(located) then
			table.insert(violations, {
				file = entry.file,
				scriptPath = entry.path,
				require = "",
				reason = "the file that the Studio tree maps does not exist",
			})
			continue
		end
		counts.files += 1
		local source = string.gsub(fs.readFile(located), "\r\n", "\n")
		local injected = settings.injectLine
		if settings.injectFile == entry.file and injected ~= nil then
			source ..= "\n" .. injected .. "\n"
		end
		for _, line in string.split(source, "\n") do
			if line == "" or string.match(line, "^%s") ~= nil then
				continue
			end
			local requested = string.match(line, "require%([\"'](%.[^\"']*)[\"']%)")
			if requested == nil then
				continue
			end
			counts.requiresChecked += 1
			local resolved, problem = resolveRelative(entry.path, requested)
			if resolved == nil then
				table.insert(violations, {
					file = entry.file,
					scriptPath = entry.path,
					require = requested,
					reason = problem or "could not resolve the path",
				})
			elseif not existing[resolved] then
				table.insert(violations, {
					file = entry.file,
					scriptPath = entry.path,
					require = requested,
					reason = ("resolves to '%s', which does not exist in the Studio instance tree"):format(resolved),
				})
			end
		end
	end
	return { ok = #violations == 0, violations = violations, counts = counts }
end

function ScenarioRequires.bind(fs: FileSystem, root: string?): Checker
	return {
		check = function(options: Options?): Result
			return ScenarioRequires.check(fs, root, options)
		end,
	}
end

return table.freeze(ScenarioRequires)
