--!strict
local fs = require("@lune/fs")
local process = require("@lune/process")

local pair, facetRef, gameRef = process.args[1], process.args[2], process.args[3]
if not (pair and facetRef and gameRef) then
	print("usage: lune run tools/lune/mkpair <dest-dir> <facet-ref> <rr-ref>")
	process.exit(2)
end
local facetRepo = process.env.FACET_REPO or process.cwd
local gameRepo = process.env.RR_REPO or (process.cwd .. "/../../../games/RascalRally/code")

local function git(repo: string, arguments: { string }): string
	local full = { "-C", repo }
	table.move(arguments, 1, #arguments, 3, full)
	local result = process.exec("git", full)
	if not result.ok then
		print(result.stderr)
		process.exit(result.code)
	end
	return (string.gsub(result.stdout, "%s+$", ""))
end

local function extract(repo: string, ref: string, destination: string, pin: string)
	fs.writeDir(destination)
	local archive = `{pair}/{pin}.tar`
	git(repo, { "archive", "--format=tar", "-o", archive, ref })
	local unpacked = process.exec("tar", { "-xf", archive, "-C", destination })
	fs.removeFile(archive)
	if not unpacked.ok then
		print(unpacked.stderr)
		process.exit(unpacked.code)
	end
	fs.writeFile(`{pair}/{pin}`, git(repo, { "rev-parse", ref }) .. "\n")
end

if fs.isDir(pair) then
	fs.removeDir(pair)
end
fs.writeDir(pair)
extract(facetRepo, facetRef, `{pair}/GameStudio/ui/Facet`, "PIN_FACET")
extract(gameRepo, gameRef, `{pair}/games/RascalRally/code`, "PIN_RR")
print(`pair: {pair}`)
print(`  PIN_FACET {fs.readFile(`{pair}/PIN_FACET`)}`)
print(`  PIN_RR    {fs.readFile(`{pair}/PIN_RR`)}`)
