--!strict

local Files = require("./files")
local Json = require("./json")

export type Row = { name: string, kind: string, p50: number, p95: number, retainedKb: number? }
export type Entry = { commit: string, date: string, rows: { Row } }

local CHART_POINTS = 30
local ARM = "pr"

local Publish = {}

local function median(values: { number }): number
	local sorted = table.clone(values)
	table.sort(sorted)
	if #sorted == 0 then
		return 0
	end
	local middle = (#sorted + 1) // 2
	if #sorted % 2 == 1 then
		return sorted[middle]
	end
	return (sorted[middle] + sorted[middle + 1]) / 2
end

type Samples = { p50: { number }, p95: { number }, retained: { number } }

local function samplesFor(store: { [string]: Samples }, order: { string }, key: string): Samples
	local found = store[key]
	if found == nil then
		found = { p50 = {}, p95 = {}, retained = {} }
		store[key] = found
		table.insert(order, key)
	end
	return found
end

function Publish.collect(directories: { string }): { Row }
	local scenes: { [string]: Samples } = {}
	local benches: { [string]: Samples } = {}
	local sceneOrder: { string } = {}
	local benchOrder: { string } = {}
	for _, directory in directories do
		local rows = Files.join(directory, "scenes.jsonl")
		if Files.isFile(rows) then
			for _, line in Files.lines(Files.read(rows)) do
				if string.find(line, "%S") ~= nil then
					local decoded = Json.decode(line)
					local row = Json.objectField(decoded, "row")
					local scene = Json.stringField(row, "scene")
					if
						Json.stringField(decoded, "label") == ARM
						and Json.stringField(row, "status") == "ok"
						and scene
					then
						local entry = samplesFor(scenes, sceneOrder, scene)
						local p50, p95 = Json.numberField(row, "p50"), Json.numberField(row, "p95")
						local retained = Json.numberField(Json.objectField(row, "memory"), "mountedRetainedKb")
						if p50 and p95 then
							table.insert(entry.p50, p50)
							table.insert(entry.p95, p95)
						end
						if retained then
							table.insert(entry.retained, retained)
						end
					end
				end
			end
		end
		for _, item in Files.list(directory) do
			if string.match(item.name, "^bench%-" .. ARM .. "%-%d+%.json$") then
				local results = Json.arrayField(Json.decode(Files.read(Files.join(directory, item.name))), "results")
				local list: Json.Array = results or Json.array()
				for _, result in list do
					local name = Json.stringField(result, "name")
					local p50, p95 = Json.numberField(result, "p50_ms"), Json.numberField(result, "p95_ms")
					if name and name ~= "zz-yardstick-cpu" and p50 and p95 then
						local entry = samplesFor(benches, benchOrder, name)
						table.insert(entry.p50, p50)
						table.insert(entry.p95, p95)
					end
				end
			end
		end
	end
	table.sort(sceneOrder)
	table.sort(benchOrder)
	local rows: { Row } = {}
	for _, name in sceneOrder do
		local entry = scenes[name]
		table.insert(rows, {
			name = name,
			kind = "scene",
			p50 = median(entry.p50),
			p95 = median(entry.p95),
			retainedKb = if #entry.retained > 0 then median(entry.retained) else nil,
		})
	end
	for _, name in benchOrder do
		local entry = benches[name]
		table.insert(rows, { name = name, kind = "microbenchmark", p50 = median(entry.p50), p95 = median(entry.p95) })
	end
	return rows
end

function Publish.encode(entry: Entry): string
	local rows: { Json.Object } = {}
	for _, row in entry.rows do
		local object = Json.object()
		Json.set(object, "name", row.name)
		Json.set(object, "kind", row.kind)
		Json.set(object, "p50", Json.float(row.p50))
		Json.set(object, "p95", Json.float(row.p95))
		if row.retainedKb ~= nil then
			Json.set(object, "retainedKb", Json.float(row.retainedKb))
		end
		table.insert(rows, object)
	end
	local document = Json.object()
	Json.set(document, "commit", entry.commit)
	Json.set(document, "date", entry.date)
	Json.set(document, "rows", Json.array(rows))
	return Json.pretty(document)
end

function Publish.decode(text: string): Entry?
	local ok, decoded = pcall(Json.decode, text)
	if not ok then
		return nil
	end
	local commit, date = Json.stringField(decoded, "commit"), Json.stringField(decoded, "date")
	local array = Json.arrayField(decoded, "rows")
	if commit == nil or date == nil or array == nil then
		return nil
	end
	local rows: { Row } = {}
	for _, raw in array do
		local name, kind = Json.stringField(raw, "name"), Json.stringField(raw, "kind")
		local p50, p95 = Json.numberField(raw, "p50"), Json.numberField(raw, "p95")
		if name and kind and p50 and p95 then
			table.insert(
				rows,
				{ name = name, kind = kind, p50 = p50, p95 = p95, retainedKb = Json.numberField(raw, "retainedKb") }
			)
		end
	end
	return { commit = commit, date = date, rows = rows }
end

local function change(current: number, previous: number?): string
	if previous == nil or previous == 0 then
		return "—"
	end
	return ("%+.1f%%"):format((current / previous - 1) * 100)
end

function Publish.render(entries: { Entry }): string
	local latest = entries[#entries]
	local previous = entries[#entries - 1]
	local before: { [string]: number } = {}
	if previous then
		for _, row in previous.rows do
			before[row.kind .. ":" .. row.name] = row.p50
		end
	end
	local lines = {
		"# Facet performance",
		"",
		`Latest: \`{latest.commit}\` on {latest.date}, measured on the CI Ubuntu runner by the paired performance shards.`,
		"Times are milliseconds per frame or operation: the median over paired rounds of each round's p50 and p95.",
		"Retained heap is the scene's mounted retained Luau heap. Change compares the p50 of the previous main commit.",
		"",
		"| Scene | p50 ms | p95 ms | Retained KiB | Change |",
		"| --- | ---: | ---: | ---: | ---: |",
	}
	local microbenchmarks: { string } = {
		"",
		"| Microbenchmark | p50 ms | p95 ms | Change |",
		"| --- | ---: | ---: | ---: |",
	}
	for _, row in latest.rows do
		local delta = change(row.p50, before[row.kind .. ":" .. row.name])
		if row.kind == "scene" then
			local retained = if row.retainedKb then ("%d"):format(math.floor(row.retainedKb + 0.5)) else "—"
			table.insert(lines, ("| %s | %.4f | %.4f | %s | %s |"):format(row.name, row.p50, row.p95, retained, delta))
		else
			table.insert(microbenchmarks, ("| %s | %.4f | %.4f | %s |"):format(row.name, row.p50, row.p95, delta))
		end
	end
	for _, line in microbenchmarks do
		table.insert(lines, line)
	end
	local start = math.max(1, #entries - CHART_POINTS + 1)
	if #entries - start + 1 >= 2 then
		table.insert(lines, "")
		table.insert(lines, `## Scene p50 over the last {#entries - start + 1} main commits`)
		for _, row in latest.rows do
			if row.kind == "scene" then
				local values: { string } = {}
				for index = start, #entries do
					local found = "0"
					for _, other in entries[index].rows do
						if other.kind == "scene" and other.name == row.name then
							found = ("%.4f"):format(other.p50)
						end
					end
					table.insert(values, found)
				end
				table.insert(lines, "")
				table.insert(lines, "```mermaid")
				table.insert(lines, "xychart-beta")
				table.insert(lines, `    title "{row.name} (p50 ms)"`)
				table.insert(lines, `    x-axis 1 --> {#values}`)
				table.insert(lines, `    line [{table.concat(values, ", ")}]`)
				table.insert(lines, "```")
			end
		end
	end
	table.insert(lines, "")
	return table.concat(lines, "\n")
end

function Publish.run(directory: string, commit: string, date: string, paired: { string }): number
	local rows = Publish.collect(paired)
	if #rows == 0 then
		print("perf publish: FAIL - the paired directories hold no pr measurements")
		return 1
	end
	local results = Files.join(directory, "results")
	Files.makeDirectory(results)
	Files.write(
		Files.join(results, `{date}-{string.sub(commit, 1, 12)}.json`),
		Publish.encode({ commit = commit, date = date, rows = rows })
	)
	local entries: { Entry } = {}
	for _, item in Files.list(results) do
		if string.sub(item.name, -5) == ".json" then
			local entry = Publish.decode(Files.read(Files.join(results, item.name)))
			if entry then
				table.insert(entries, entry)
			end
		end
	end
	table.sort(entries, function(left: Entry, right: Entry): boolean
		if left.date ~= right.date then
			return left.date < right.date
		end
		return left.commit < right.commit
	end)
	Files.write(Files.join(directory, "README.md"), Publish.render(entries))
	print(`perf publish: {#rows} rows for {commit}`)
	return 0
end

return table.freeze(Publish)
