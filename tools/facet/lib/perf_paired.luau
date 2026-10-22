--!strict

local Json = require("./json")

export type Rounds = { [number]: Json.Object }

export type Bench = { path: string, round: number, document: Json.Object }
export type Scope = { rounds: number, scenes: { string }, bench: boolean }

type Cell = { first: number?, second: number?, ratio: number?, paired: { number } }

local Paired = {}

local function positive(value: unknown): boolean
	return type(value) == "number" and value > 0 and value < math.huge
end

function Paired.benchOutcome(code: number, document: unknown): { string }
	local errors: { string } = {}
	if code ~= 0 then
		table.insert(errors, `benchmark command exited {code}`)
	end
	if
		Json.field(document, "schema") ~= "facet-bench/1"
		or Json.field(document, "status") ~= "PASS"
		or Json.field(document, "proofStatus") ~= "stable-cpu-rate-trend"
	then
		table.insert(errors, "benchmark report is missing, failed or unstable")
	end
	local drift = Json.numberField(document, "yardstickMedianDriftPct")
	if
		not positive(Json.field(document, "yardstickP95Ms"))
		or drift == nil
		or drift ~= drift
		or drift < 0
		or drift > 15
	then
		table.insert(errors, "benchmark yardstick is missing or unstable")
	end
	local rows = Json.arrayField(document, "results")
	if rows == nil or #rows == 0 then
		table.insert(errors, "benchmark measurements are missing")
		return errors
	end
	local names: { [string]: boolean } = {}
	for _, row in rows do
		local name = Json.stringField(row, "name")
		local p50, p95, p99 =
			Json.numberField(row, "p50_ms"), Json.numberField(row, "p95_ms"), Json.numberField(row, "p99_ms")
		local samples = Json.numberField(row, "samples")
		if name == nil or name == "" or names[name] then
			table.insert(errors, "benchmark measurement has a missing or duplicate name")
		else
			names[name] = true
		end
		if
			not positive(p50)
			or not positive(p95)
			or not positive(p99)
			or (p50 ~= nil and p95 ~= nil and p50 > p95)
			or (p95 ~= nil and p99 ~= nil and p95 > p99)
			or samples == nil
			or samples < 1
			or samples % 1 ~= 0
		then
			table.insert(errors, `benchmark {name or "unknown"} has invalid measurements`)
		end
	end
	return errors
end

function Paired.validate(
	scope: Scope,
	entries: { Json.Object },
	firstBenches: { Bench },
	secondBenches: { Bench },
	first: string,
	second: string
): { string }
	local errors: { string } = {}
	local selected: { [string]: boolean } = {}
	for _, scene in scope.scenes do
		selected[scene] = true
	end
	local seen: { [string]: boolean } = {}
	for _, entry in entries do
		local label, round = Json.stringField(entry, "label"), Json.numberField(entry, "round")
		if label ~= first and label ~= second then
			continue
		end
		local row = Json.field(entry, "row")
		local scene = Json.stringField(row, "scene")
		if
			round == nil
			or round < 1
			or round > scope.rounds
			or round % 1 ~= 0
			or scene == nil
			or not selected[scene]
		then
			table.insert(errors, "scene result is outside the expected comparison scope")
			continue
		end
		local key = `{label}\0{round}\0{scene}`
		local p50, p95 = Json.numberField(row, "p50"), Json.numberField(row, "p95")
		if
			seen[key]
			or Json.field(row, "status") ~= "ok"
			or not positive(p50)
			or not positive(p95)
			or (p50 ~= nil and p95 ~= nil and p50 > p95)
		then
			table.insert(errors, `{label} round {round} scene {scene} is duplicate or unavailable`)
		end
		seen[key] = true
	end
	for _, label in { first, second } do
		for round = 1, scope.rounds do
			for _, scene in scope.scenes do
				if not seen[`{label}\0{round}\0{scene}`] then
					table.insert(errors, `{label} round {round} scene {scene} is missing`)
				end
			end
		end
	end
	local expected: { [string]: boolean }? = nil
	for index, benches in { firstBenches, secondBenches } do
		local label = if index == 1 then first else second
		local rounds: { [number]: boolean } = {}
		for _, bench in benches do
			if
				not scope.bench
				or bench.round < 1
				or bench.round > scope.rounds
				or bench.round % 1 ~= 0
				or rounds[bench.round]
			then
				table.insert(errors, `{label} benchmark round {bench.round} is outside the expected comparison scope`)
			end
			rounds[bench.round] = true
			for _, detail in Paired.benchOutcome(0, bench.document) do
				table.insert(errors, `{label} round {bench.round}: {detail}`)
			end
			local names: { [string]: boolean } = {}
			for _, row in Json.arrayField(bench.document, "results") or Json.array() do
				local name = Json.stringField(row, "name")
				if name then
					names[name] = true
				end
			end
			if expected then
				for name in expected do
					if not names[name] then
						table.insert(errors, `{label} round {bench.round}: benchmark {name} is missing`)
					end
				end
				for name in names do
					if not expected[name] then
						table.insert(
							errors,
							`{label} round {bench.round}: benchmark {name} has no matching measurement`
						)
					end
				end
			else
				expected = names
			end
		end
		if scope.bench then
			for round = 1, scope.rounds do
				if not rounds[round] then
					table.insert(errors, `{label} benchmark round {round} is missing`)
				end
			end
		end
	end
	return errors
end

Paired.SCENES = {
	"hud-binding-storm",
	"settings-churn",
	"scroll-focus-traversal",
	"collection-mutation",
	"animation-interruption",
	"locale-textsize-change",
	"async-image-burst",
	"shadow-storm",
	"virtual-list-scroll",
	"native-scroll-drag",
	"dense-hud",
	"stylesheet-state-churn",
	"async-image-grid",
	"screen-lifecycle-churn",
	"theme-swap-flat",
	"theme-swap-metrics",
	"dense-motion",
	"control-motion",
	"theme-swap-assets",
	"lab-dense-scroll",
	"lab-collection-churn",
	"adaptive-navigation-images",
	"navigation-customization",
	"alert-present-dismiss",
	"picker-menu-open-close",
	"picker-segmented-textsize",
	"radial-menu-open-close",
}

function Paired.median(values: { number }): number?
	if #values == 0 then
		return nil
	end
	local sorted = table.clone(values)
	table.sort(sorted)
	local middle = #sorted // 2
	if #sorted % 2 == 1 then
		return sorted[middle + 1]
	end
	return (sorted[middle] + sorted[middle + 1]) / 2
end

function Paired.number(value: number?, digits: number?): string
	if value == nil then
		return "n/a"
	end
	return ("%." .. tostring(digits or 4) .. "f"):format(value)
end

function Paired.consistentSlower(ratio: number?, paired: { number }): boolean
	if ratio == nil or ratio <= 1.05 or #paired == 0 then
		return false
	end
	for _, value in paired do
		if value <= 1 then
			return false
		end
	end
	return true
end

function Paired.sceneRow(output: string): Json.Object?
	local normalized = string.gsub(output, "\r\n", "\n")
	for _, text in string.split(normalized, "\n") do
		if string.sub(text, 1, 2) == "@@" then
			return Json.asObject(Json.decode(string.sub(text, 3)))
		end
	end
	return nil
end

local function numeric(value: unknown): number
	return if type(value) == "number" then value else 0
end

local function sortedRounds(rounds: Rounds): { number }
	local list: { number } = {}
	for round in rounds do
		table.insert(list, round)
	end
	table.sort(list)
	return list
end

local function values(rounds: Rounds, field: string): { number }
	local list: { number } = {}
	for _, round in sortedRounds(rounds) do
		table.insert(list, numeric(rounds[round][field]))
	end
	return list
end

local function cell(left: Rounds, right: Rounds, field: string): Cell
	local first = Paired.median(values(left, field))
	local second = Paired.median(values(right, field))
	local ratio = if first ~= nil and first ~= 0 and second ~= nil then second / first else nil
	local paired: { number } = {}
	for _, round in sortedRounds(left) do
		local other = right[round]
		local base = numeric(left[round][field])
		if other ~= nil and base > 0 then
			table.insert(paired, numeric(other[field]) / base)
		end
	end
	return { first = first, second = second, ratio = ratio, paired = paired }
end

local function range(list: { number }, digits: number): string
	if #list == 0 then
		return "n/a"
	end
	local low, high = math.huge, -math.huge
	for _, value in list do
		low = math.min(low, value)
		high = math.max(high, value)
	end
	return ("%." .. digits .. "f-%." .. digits .. "f"):format(low, high)
end

local function okRounds(rounds: { [number]: Json.Object }?): Rounds
	local kept: Rounds = {}
	if rounds == nil then
		return kept
	end
	for round, row in rounds do
		if Json.field(row, "status") == "ok" then
			kept[round] = row
		end
	end
	return kept
end

local function isEmpty(rounds: Rounds): boolean
	return next(rounds) == nil
end

function Paired.sceneTable(entries: { Json.Object }, first: string, second: string): { string }
	local data: { [string]: { [string]: { [number]: Json.Object } } } = {}
	local order: { string } = {}
	for _, entry in entries do
		local row = Json.asObject(entry.row) or Json.object()
		local scene = tostring(Json.field(row, "scene"))
		if data[scene] == nil then
			data[scene] = {}
			table.insert(order, scene)
		end
		local label = tostring(Json.field(entry, "label"))
		local byLabel = data[scene][label]
		if byLabel == nil then
			byLabel = {}
			data[scene][label] = byLabel
		end
		byLabel[numeric(Json.field(entry, "round"))] = row
	end
	local lines: { string } = {
		("| Scene | %s p50 | %s p50 | p50 ratio | p50 paired range | %s p95 | %s p95 | p95 ratio | p95 paired range | %s p95 spread | %s p95 spread | Flag |"):format(
			first,
			second,
			first,
			second,
			first,
			second
		),
		"|---|---:|---:|---:|---|---:|---:|---:|---|---|---|---|",
	}
	for _, scene in order do
		local left = okRounds(data[scene][first])
		local right = okRounds(data[scene][second])
		local p50 = cell(left, right, "p50")
		local p95 = cell(left, right, "p95")
		local flag = ""
		if isEmpty(left) then
			local statuses: { [string]: boolean } = {}
			local firstRows: { [number]: Json.Object } = data[scene][first] or {}
			for _, row in firstRows do
				local status = Json.field(row, "status")
				statuses[if status == nil then "?" else tostring(status)] = true
			end
			local list: { string } = {}
			for status in statuses do
				table.insert(list, status)
			end
			table.sort(list)
			flag = ("%s unavailable (%s)"):format(first, table.concat(list, "/"))
		elseif isEmpty(right) then
			flag = ("%s unavailable"):format(second)
		else
			local slower: { string } = {}
			if Paired.consistentSlower(p50.ratio, p50.paired) then
				table.insert(slower, "p50")
			end
			if Paired.consistentSlower(p95.ratio, p95.paired) then
				table.insert(slower, "p95")
			end
			if #slower > 0 then
				flag = ("%s slower (%s)"):format(second, table.concat(slower, ", "))
			end
		end
		table.insert(
			lines,
			("| %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |"):format(
				scene,
				Paired.number(p50.first),
				Paired.number(p50.second),
				Paired.number(p50.ratio, 3),
				range(p50.paired, 2),
				Paired.number(p95.first),
				Paired.number(p95.second),
				Paired.number(p95.ratio, 3),
				range(p95.paired, 2),
				range(values(left, "p95"), 4),
				range(values(right, "p95"), 4),
				flag
			)
		)
	end
	return lines
end

local function benchResults(benches: { Bench }): { [string]: Rounds }
	local results: { [string]: Rounds } = {}
	for _, bench in benches do
		local entries: Json.Array = Json.arrayField(bench.document, "results") or Json.array()
		for _, entry in entries do
			local object = Json.asObject(entry)
			if object ~= nil and Json.field(object, "p50_ms") ~= nil then
				local name = tostring(Json.field(object, "name"))
				local rounds = results[name]
				if rounds == nil then
					rounds = {}
					results[name] = rounds
				end
				rounds[bench.round] = object
			end
		end
	end
	return results
end

function Paired.benchTables(
	firstBenches: { Bench },
	secondBenches: { Bench },
	first: string,
	second: string
): { string }
	local left = benchResults(firstBenches)
	local right = benchResults(secondBenches)
	if next(left) == nil and next(right) == nil then
		return {}
	end
	local lines: { string } = {
		"",
		("| Microbenchmark | %s p50 | %s p50 | p50 ratio | p50 paired range | %s p95 | %s p95 | p95 ratio | Flag |"):format(
			first,
			second,
			first,
			second
		),
		"|---|---:|---:|---:|---|---:|---:|---:|---|",
	}
	local names: { [string]: boolean } = {}
	for name in left do
		names[name] = true
	end
	for name in right do
		names[name] = true
	end
	local sorted: { string } = {}
	for name in names do
		table.insert(sorted, name)
	end
	table.sort(sorted)
	for _, name in sorted do
		local leftRounds = left[name] or {}
		local rightRounds = right[name] or {}
		local p50 = cell(leftRounds, rightRounds, "p50_ms")
		local p95 = cell(leftRounds, rightRounds, "p95_ms")
		local slower: { string } = {}
		if Paired.consistentSlower(p50.ratio, p50.paired) then
			table.insert(slower, "p50")
		end
		if Paired.consistentSlower(p95.ratio, p95.paired) then
			table.insert(slower, "p95")
		end
		local flag = if #slower > 0 and string.sub(name, 1, 3) ~= "zz-"
			then ("%s slower (%s)"):format(second, table.concat(slower, ", "))
			else ""
		table.insert(
			lines,
			("| %s | %s | %s | %s | %s | %s | %s | %s | %s |"):format(
				name,
				Paired.number(p50.first),
				Paired.number(p50.second),
				Paired.number(p50.ratio, 3),
				range(p50.paired, 2),
				Paired.number(p95.first),
				Paired.number(p95.second),
				Paired.number(p95.ratio, 3),
				flag
			)
		)
	end
	table.insert(lines, "")
	table.insert(lines, "| Bench run | Yardstick p95 ms | Yardstick p95 drift % | CPU median drift % |")
	table.insert(lines, "|---|---:|---:|---:|")
	for _, benches in { firstBenches, secondBenches } do
		local ordered = table.clone(benches)
		table.sort(ordered, function(a: Bench, b: Bench): boolean
			return a.round < b.round
		end)
		for _, bench in ordered do
			local stem = string.match(bench.path, "([^/\\]+)%.json$") or bench.path
			table.insert(
				lines,
				("| %s | %.4f | %.1f | %.1f |"):format(
					string.sub(stem, 7),
					numeric(Json.field(bench.document, "yardstickP95Ms")),
					numeric(Json.field(bench.document, "yardstickDriftPct")),
					numeric(Json.field(bench.document, "yardstickMedianDriftPct"))
				)
			)
		end
	end
	return lines
end

local function percent(text: string): string
	local ratio = tonumber(text)
	if ratio == nil then
		return "n/a"
	end
	local change = (ratio - 1) * 100
	return ("%s%.1f%%"):format(if change < 0 then "-" else "+", math.abs(change))
end

function Paired.summary(lines: { string }, first: string, second: string): { string }
	local scenes, benches, unavailable = 0, 0, 0
	local slower: { string } = {}
	local kind: string? = nil
	for _, line in lines do
		if string.sub(line, 1, 8) == "| Scene " then
			kind = "scene"
			continue
		elseif string.sub(line, 1, 17) == "| Microbenchmark " then
			kind = "bench"
			continue
		elseif string.sub(line, 1, 4) == "|---" then
			continue
		elseif string.sub(line, 1, 1) ~= "|" then
			kind = nil
			continue
		elseif kind == nil then
			continue
		end
		local cells: { string } = {}
		for _, value in string.split(line, "|") do
			table.insert(cells, (string.gsub(value, "^%s*(.-)%s*$", "%1")))
		end
		table.remove(cells, 1)
		table.remove(cells)
		local name, flag = cells[1], cells[#cells]
		if kind == "scene" then
			scenes += 1
		else
			benches += 1
		end
		if string.find(flag, "unavailable", 1, true) then
			unavailable += 1
		elseif string.find(flag, second .. " slower (", 1, true) then
			local which = string.match(flag, "%((.-)%)") or ""
			table.insert(
				slower,
				("| %s%s | %s | %s | %s |"):format(
					name,
					if kind == "bench" then " (microbenchmark)" else "",
					percent(cells[4]),
					percent(cells[8]),
					which
				)
			)
		end
	end
	local measured = ("%d scenes%s"):format(
		scenes,
		if benches > 0 then (" and %d microbenchmarks"):format(benches) else ""
	)
	local summary: { string } = {}
	if #slower == 0 then
		table.insert(summary, "### Paired performance: PASS")
		table.insert(summary, "")
		table.insert(summary, ("%s is not consistently slower than %s in any of %s."):format(second, first, measured))
	else
		table.insert(summary, "### Paired performance: FAIL")
		table.insert(summary, "")
		table.insert(
			summary,
			("%s is consistently slower than %s in %d of %s."):format(second, first, #slower, measured)
		)
		table.insert(summary, "")
		table.insert(summary, "| Slower | p50 change | p95 change | Slower at |")
		table.insert(summary, "|---|---:|---:|---|")
		for _, row in slower do
			table.insert(summary, row)
		end
	end
	if unavailable > 0 then
		table.insert(summary, "")
		table.insert(summary, ("%d measurements were unavailable; see the full table."):format(unavailable))
	end
	table.insert(summary, "")
	table.insert(summary, "Consistently slower means the median ratio is above 1.05 and every paired round is slower.")
	return summary
end

function Paired.benchRound(name: string, label: string): number?
	if string.sub(name, 1, #label + 7) ~= "bench-" .. label .. "-" or string.sub(name, -5) ~= ".json" then
		return nil
	end
	local digits = string.match(name, "%-(%d+)%.json$")
	return if digits ~= nil then tonumber(digits) else nil
end

return table.freeze(Paired)
