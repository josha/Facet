--!strict

local fs = require("@std/fs")
local json = require("@std/json")
local Cli = require("../lib/cli")
local Raster = require("../lib/raster")
local targets = require("../art")
local Compare = require("../art/compare")
local Sample = require("../art/sample")

type Image = Raster.Image

local USAGE = [[usage: lute run tools/facet art <target> [--check] [--json]

Regenerate the procedural PNG art and write each file whose pixels changed.
A file with the same pixels is not rewritten, so its bytes and hashes stay.

targets:
  all                every target below except sample
  sample             assets/themes/plate-samples.json from the committed plates
%s

options:
  --check    regenerate in memory and compare with the committed files; write nothing]]

local function readImage(path: string): Image?
	if not fs.exists(path) then
		return nil
	end
	return Raster.Png.decode(buffer.fromstring(fs.readFileToString(path)))
end

local function parent(path: string): string?
	return string.match(path, "^(.*)/[^/]+$")
end

local function writeImage(path: string, image: Image)
	local folder = parent(path)
	if folder ~= nil and not fs.exists(folder) then
		fs.createDirectory(folder, { makeParents = true })
	end
	fs.writeStringToFile(path, buffer.tostring(Raster.Png.encode(image)))
end

type Row = { path: string, status: string, detail: string }

local function runTarget(name: string, check: boolean, rows: { Row }): boolean
	for _, target in targets do
		if target.name == name then
			local passed = true
			for _, output in target.generate() do
				local committed = readImage(output.path)
				local row: Row
				if committed == nil then
					row = { path = output.path, status = "missing", detail = "no committed file" }
				else
					local metrics = Compare.metrics(committed, output.image)
					row = {
						path = output.path,
						status = if metrics.identical then "identical" else "differs",
						detail = Compare.describe(metrics),
					}
				end
				if row.status ~= "identical" then
					if check then
						passed = false
					else
						writeImage(output.path, output.image)
						row.status = "written"
					end
				end
				table.insert(rows, row)
			end
			return passed
		end
	end
	error(("unknown art target '%s'"):format(name), 0)
end

local function targetList(): string
	local lines: { string } = {}
	for _, target in targets do
		table.insert(lines, ("  %-18s %s"):format(target.name, target.summary))
	end
	return table.concat(lines, "\n")
end

local function run(invocation: Cli.Invocation): number
	local name = invocation.positional[1]
	if name == nil then
		print(USAGE:format(targetList()))
		return 2
	end
	local check = Cli.switch(invocation, "check")
	if name == "sample" then
		return Sample.run(invocation)
	end
	local names: { string } = {}
	if name == "all" then
		for _, target in targets do
			table.insert(names, target.name)
		end
	else
		table.insert(names, name)
	end
	local rows: { Row } = {}
	local passed = true
	local started = os.clock()
	for _, targetName in names do
		local ok, result = pcall(runTarget, targetName, check, rows)
		if not ok then
			print(("facet art: %s"):format(tostring(result)))
			return 2
		end
		passed = passed and result
	end
	local counts: { [string]: number } = {}
	local lines: { string } = {}
	for _, row in rows do
		counts[row.status] = (counts[row.status] or 0) + 1
		if row.status ~= "identical" or Cli.switch(invocation, "verbose") then
			table.insert(lines, ("  %-9s %s  (%s)"):format(row.status, row.path, row.detail))
		end
	end
	local summary = ("art %s: %d images, %d identical, %d written, %d differ, %d missing (%.1fs)"):format(
		table.concat(names, ", "),
		#rows,
		counts.identical or 0,
		counts.written or 0,
		counts.differs or 0,
		counts.missing or 0,
		os.clock() - started
	)
	table.insert(lines, summary)
	local report: { [string]: json.Value } = { passed = passed, check = check }
	local entries: { json.Value } = {}
	for _, row in rows do
		local entry: { [string]: json.Value } = { path = row.path, status = row.status, detail = row.detail }
		table.insert(entries, entry)
	end
	report.images = entries
	Cli.emit(invocation, report, table.concat(lines, "\n"))
	return if passed then 0 else 1
end

local command: Cli.Command = {
	name = "art",
	summary = "Regenerate or check the procedural theme art, icons and plate samples.",
	usage = USAGE:format(targetList()),
	run = run,
}

return command
