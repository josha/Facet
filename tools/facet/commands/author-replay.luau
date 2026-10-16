--!strict
local Cli = require("../lib/cli")
local Files = require("../lib/files")
local Json = require("../lib/json")
local Run = require("../lib/run")
local Static = require("../lib/static_findings")
local Output = require("../lib/verify_output")

local USAGE =
	"usage: lute run tools/facet author-replay RUN_DIRECTORY --out DIR [--report RELATIVE_FILE]... [--props Control=SOURCE_FILE]..."

local function run(invocation: Cli.Invocation): number
	local directory = invocation.positional[1]
	local out = Cli.flag(invocation, "out")
	if directory == nil or out == nil then
		print(USAGE)
		return 2
	end
	local docsBefore, docsAfter, queries = 0, 0, 0
	local staticBefore, staticAfter = 0, 0
	local explicitBefore, explicitAfter = 0, 0
	local reportsBefore, reportsAfter, reports = 0, 0, 0
	local rows: { string } = { "kind\tquery\tbefore\tafter" }
	local seenReports: { [string]: boolean } = {}
	local reportPaths = table.clone(invocation.repeated.report or {})
	for _, line in Files.lines(Files.read(Files.join(directory, "transcript.jsonl"))) do
		local body = string.match(line, "^[^\t]+\t(.*)$")
		if body == nil then
			continue
		end
		local event = Json.decode(body)
		local item = Json.objectField(event, "item")
		if
			Json.stringField(event, "type") ~= "item.completed"
			or item == nil
			or Json.stringField(item, "type") ~= "command_execution"
		then
			continue
		end
		local command = Json.stringField(item, "command") or ""
		local output = Json.stringField(item, "aggregated_output") or ""
		for tail in string.gmatch(command, "lute run tools/facet docs([^;\r\n'\"]*)") do
			local arguments = { "run", "tools/facet", "docs" }
			for word in string.gmatch(tail, "%S+") do
				table.insert(arguments, word)
			end
			local before = Run.capture(
				{ Run.lute(), table.unpack(arguments) },
				{ cwd = Files.join(directory, "workspace"), timeout = 30 }
			)
			local after = Run.capture({ Run.lute(), table.unpack(arguments) }, { timeout = 30 })
			assert(before.ok and after.ok, before.stderr .. after.stderr)
			queries += 1
			docsBefore += #before.stdout
			docsAfter += #after.stdout
			table.insert(rows, `docs\t{tail}\t{#before.stdout}\t{#after.stdout}`)
		end
		if
			(staticBefore == 0 or (explicitBefore == 0 and string.find(command, "verify --static", 1, true) ~= nil))
			and string.find(command, "tools/facet verify", 1, true)
			and string.find(output, "error [types]", 1, true)
		then
			local findings: { Static.Finding } = {}
			local static: { string } = {}
			local active: Static.Finding? = nil
			local count = 0
			local locations: { string } = {}
			local function finish()
				local current = active
				if current == nil then
					return
				end
				for index = 1, count do
					local copy = table.clone(current)
					copy.location = locations[index] or "additional saved location"
					table.insert(findings, copy)
				end
			end
			for _, entry in Files.lines(output) do
				if string.sub(entry, 1, 21) == "Full static findings:" then
					break
				end
				local severity, rule, message, quantity =
					string.match(entry, "^(%a+) %[(.-)%] (.-) %((%d+) finding%(s%)%)$")
				if severity == nil then
					severity, rule, quantity = string.match(entry, "^(warning) %[(.-)%] (%d+) finding%(s%)")
					message = "saved warning"
				end
				if severity and rule and message then
					finish()
					count, locations = tonumber(quantity) or 1, {}
					active = {
						severity = if severity == "error" then "error" else "warning",
						rule = rule,
						message = message,
						location = "",
					}
					table.insert(static, entry)
				elseif active and string.sub(entry, 1, 4) == "    " then
					table.insert(static, entry)
					if string.sub(entry, 1, 10) == "    hint: " then
						active.hint = string.sub(entry, 11)
					elseif not string.match(entry, "^    and %d+ more$") then
						table.insert(locations, string.sub(entry, 5))
					end
				end
			end
			finish()
			local before = table.concat(static, "\n") .. "\n"
			local after = table.concat(
				Static.render(findings, string.find(command, "verify --static", 1, true) == nil),
				"\n"
			) .. "\n"
			if staticBefore == 0 then
				staticBefore, staticAfter = #before, #after
				Files.write(Files.join(out, "static-before.txt"), before)
				Files.write(Files.join(out, "static-after.txt"), after)
			end
			if explicitBefore == 0 and string.find(command, "verify --static", 1, true) then
				explicitBefore, explicitAfter = #before, #after
				Files.write(Files.join(out, "explicit-static-before.txt"), before)
				Files.write(Files.join(out, "explicit-static-after.txt"), after)
			end
		end
		for relative in string.gmatch(command, "(artifacts/[%w_/-]+/report%.txt)") do
			table.insert(reportPaths, relative)
		end
	end
	for _, relative in reportPaths do
		if seenReports[relative] or string.find(relative, "facet-lint", 1, true) then
			continue
		end
		local file = Files.join(directory, "workspace", relative)
		if not Files.isFile(file) then
			continue
		end
		seenReports[relative] = true
		local text = Files.text(file)
		local lines = Files.lines(text)
		local filters = Output.queries(lines, Files.parent(relative))
		if #filters == 0 then
			continue
		end
		local device = string.match(filters[1], "%-%-device (%S+)")
		local rule = string.match(filters[1], "%-%-rule (%S+)")
		local after = table.concat(Output.query(lines, { device = device, rule = rule }), "\n") .. "\n"
		reports += 1
		reportsBefore += #text
		reportsAfter += #after
		Files.write(Files.join(out, `report-{reports}-after.txt`), after)
		table.insert(rows, `report\t{relative} -> {device}/{rule} page 1\t{#text}\t{#after}`)
	end
	local propsBefore, propsAfter = 0, 0
	local replacements: { string } = invocation.repeated.props or {}
	for _, spec in replacements do
		local control, source = string.match(spec, "^([%w_]+)=(.+)$")
		assert(control and source, "--props needs Control=SOURCE_FILE")
		local before = Files.read(Files.join(directory, "workspace", source))
		local after = Run.capture({ Run.lute(), "run", "tools/facet", "docs", control .. ".props" }, { timeout = 30 })
		assert(after.ok, after.stderr)
		propsBefore += #before
		propsAfter += #after.stdout
		table.insert(rows, `props\t{source} -> {control}.props\t{#before}\t{#after.stdout}`)
	end
	local summary =
		`docs ({queries} queries): {docsBefore} -> {docsAfter} bytes\nfirst static findings: {staticBefore} -> {staticAfter} bytes\nfirst --static findings: {explicitBefore} -> {explicitAfter} bytes\nreports ({reports}, first failing group page): {reportsBefore} -> {reportsAfter} bytes\noption source replacements: {propsBefore} -> {propsAfter} bytes`
	Files.write(Files.join(out, "queries.tsv"), table.concat(rows, "\n") .. "\n")
	Files.write(Files.join(out, "summary.txt"), summary .. "\n")
	print(summary)
	return 0
end

return {
	name = "author-replay",
	summary = "Measure saved author queries without changing the saved run.",
	usage = USAGE,
	values = { "out", "report", "props" },
	run = run,
} :: Cli.Command
