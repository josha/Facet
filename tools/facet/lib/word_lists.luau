--!strict

local Case = require("./case")
local Files = require("./files")
local Hash = require("./hash")

export type Mismatch = { name: string, problem: string }

export type Verification = {
	manifest: string,
	refusal: string?,
	recorded: number,
	mismatches: { Mismatch },
}

local WordLists = {}

WordLists.OUT_DIR = "examples/gallery/examples/words"
WordLists.MANIFEST = "manifest.luau"
WordLists.REGENERATE = "lute run tools/facet words"

function WordLists.hashText(contents: string): string
	return Hash.sha256Text(contents)
end

function WordLists.recordedHashes(manifest: string): { [string]: string }
	local recorded: { [string]: string } = {}
	for name, digest in string.gmatch(manifest, '%["([%w_%.]+%.luau)"%] = "([0-9a-f]+)"') do
		if name ~= nil and digest ~= nil and #digest == 64 then
			recorded[name] = digest
		end
	end
	return recorded
end

function WordLists.verify(root: string): Verification
	local directory = Files.join(root, WordLists.OUT_DIR)
	local manifestPath = Files.join(WordLists.OUT_DIR, WordLists.MANIFEST)
	local verification: Verification = { manifest = manifestPath, refusal = nil, recorded = 0, mismatches = {} }
	local absoluteManifest = Files.join(directory, WordLists.MANIFEST)
	if not Files.isFile(absoluteManifest) then
		verification.refusal = ("%s is missing; run the generator"):format(manifestPath)
		return verification
	end
	local recorded = WordLists.recordedHashes(Files.text(absoluteManifest))
	local names: { string } = {}
	for name in recorded do
		table.insert(names, name)
	end
	table.sort(names)
	verification.recorded = #names
	if #names == 0 then
		verification.refusal = "the manifest records no file hashes.\n  Finding nothing is a failure here, not a pass."
		return verification
	end
	for _, name in names do
		local path = Files.join(directory, name)
		if not Files.isFile(path) then
			table.insert(verification.mismatches, { name = name, problem = "missing" })
			continue
		end
		local actual = WordLists.hashText(Files.read(path))
		if actual ~= recorded[name] then
			table.insert(
				verification.mismatches,
				{ name = name, problem = ("%s != recorded %s"):format(actual, recorded[name]) }
			)
		end
	end
	return verification
end

function WordLists.findings(root: string): { string }
	local verification = WordLists.verify(root)
	local refusal = verification.refusal
	if refusal ~= nil then
		return { (string.gsub(refusal, "\n%s*", " ")) }
	end
	local findings: { string } = {}
	for _, mismatch in verification.mismatches do
		table.insert(
			findings,
			("%s/%s: %s; regenerate with `%s`"):format(
				WordLists.OUT_DIR,
				mismatch.name,
				mismatch.problem,
				WordLists.REGENERATE
			)
		)
	end
	return findings
end

local function fixture(files: { [string]: string }, body: (root: string) -> string?): string?
	local root = Files.temporaryDirectory("facet-word-data-")
	for relative, contents in files do
		Files.write(Files.join(root, WordLists.OUT_DIR, relative), contents)
	end
	local ok, result = pcall(body, root)
	Files.remove(root)
	if not ok then
		return "raised: " .. tostring(result)
	end
	return result
end

local function manifestFor(files: { [string]: string }): string
	local names: { string } = {}
	for name in files do
		table.insert(names, name)
	end
	table.sort(names)
	local lines = { "--!strict", "", "return table.freeze({", '\t["files"] = {' }
	for _, name in names do
		table.insert(lines, ('\t\t["%s"] = "%s",'):format(name, Hash.sha256(files[name])))
	end
	table.insert(lines, "\t},")
	table.insert(lines, "})")
	return table.concat(lines, "\n") .. "\n"
end

function WordLists.cases(): { Case.Case }
	return {
		{
			name = "word data: a file whose hash does not match is refused",
			run = function(): string?
				return fixture({
					["manifest.luau"] = 'return { files = { ["len5.luau"] = "' .. string.rep("0", 64) .. '" } }\n',
					["len5.luau"] = "return {}\n",
				}, function(root: string): string?
					local verification = WordLists.verify(root)
					return Case.first(
						Case.equal(#verification.mismatches, 1, "mismatches"),
						Case.expect(#WordLists.findings(root) == 1, "the rule reported no finding")
					)
				end)
			end,
		},
		{
			name = "word data: a manifest recording nothing is refused",
			run = function(): string?
				return fixture({ ["manifest.luau"] = "return { files = {} }\n" }, function(root: string): string?
					local verification = WordLists.verify(root)
					return Case.first(
						Case.expect(verification.refusal ~= nil, "an empty manifest passed"),
						Case.expect(#WordLists.findings(root) == 1, "the rule reported no finding")
					)
				end)
			end,
		},
		{
			name = "word data: a missing manifest is refused",
			run = function(): string?
				return fixture({ ["len5.luau"] = "return {}\n" }, function(root: string): string?
					local findings = WordLists.findings(root)
					return Case.expect(
						#findings == 1 and string.find(findings[1], "is missing", 1, true) ~= nil,
						"a missing manifest passed"
					)
				end)
			end,
		},
		{
			name = "word data: a missing generated file is refused",
			run = function(): string?
				local files = { ["len5.luau"] = "return {}\n" }
				return fixture({ ["manifest.luau"] = manifestFor(files) }, function(root: string): string?
					local verification = WordLists.verify(root)
					return Case.first(
						Case.equal(#verification.mismatches, 1, "mismatches"),
						Case.equal(verification.mismatches[1] and verification.mismatches[1].problem, "missing")
					)
				end)
			end,
		},
		{
			name = "word data: matching files pass and CRLF hashes as LF",
			run = function(): string?
				local files = { ["len2.luau"] = "--!strict\nreturn {}\n", ["solutions.luau"] = "return {\n}\n" }
				return fixture({
					["manifest.luau"] = manifestFor(files),
					["len2.luau"] = "--!strict\r\nreturn {}\r\n",
					["solutions.luau"] = files["solutions.luau"],
				}, function(root: string): string?
					local verification = WordLists.verify(root)
					return Case.first(
						Case.equal(verification.refusal, nil, "refusal"),
						Case.equal(verification.recorded, 2, "recorded"),
						Case.equal(#verification.mismatches, 0, "mismatches"),
						Case.same(WordLists.findings(root), {}, "findings")
					)
				end)
			end,
		},
	}
end

return table.freeze(WordLists)
