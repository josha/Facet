--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local fs = require("@lune/fs")
	local process = require("@lune/process")
	local serde = require("@lune/serde")

	local DIR = process.env.FACET_FOCUS_ATLAS or "tests/fixtures/focus_atlas"
	local FAMILIES = { "dpad", "stick", "keys" }

	local function load(file: string): any
		local atlas = serde.decode("json", fs.readFile(`{DIR}/{file}`))
		local keys = `{DIR}/{string.sub(file, 1, -6)}--keys.json`
		if fs.isFile(keys) then
			local pass = serde.decode("json", fs.readFile(keys))
			atlas.moves.keys = pass.moves.keys
			if pass.scenes then
				atlas.scenes = atlas.scenes or {}
				atlas.scenes.keys = pass.scenes.keys
			end
		end
		return atlas
	end

	local function entryOf(atlas: any, container: string): string?
		local entry = atlas.containers[container].entry
		local first: string? = nil
		for _, stop in atlas.stops do
			if stop.chain[1] == container then
				first = first or stop.path
				if entry and string.match(stop.path, "([^/]+)$") == entry then
					return stop.path
				end
			end
		end
		return first
	end

	local function problemsOf(atlas: any): { string }
		local problems: { string } = {}
		local known: { [string]: boolean } = {}
		for _, stop in atlas.stops do
			known[stop.path] = true
		end
		local recorded = type(atlas.scenes) == "table"
		local edges: { [string]: { string } } = {}
		for _, family in FAMILIES do
			local rows = atlas.moves[family]
			if type(rows) ~= "table" then
				continue
			end
			for from, row in rows do
				if type(row) ~= "table" then
					continue
				end
				for key, target in row do
					if type(target) ~= "string" then
						continue
					end
					if string.sub(target, 1, 10) == "unsettled:" then
						table.insert(problems, `unsettled: {from} {key} {target}`)
						continue
					end
					local landed: string? = if known[target] then target else nil
					if landed == nil and atlas.containers[target] then
						landed = entryOf(atlas, target) or target
					end
					if landed == nil and recorded then
						local scene = ((atlas.scenes[family] or {})[from] or {})[key]
						for _, added in (if scene then scene.added else nil) or {} do
							if added.path == target then
								landed = target
							end
						end
						if landed == nil then
							table.insert(problems, `unknown target: {from} {key} -> {target}`)
						end
					end
					if landed and known[landed] then
						edges[from] = edges[from] or {}
						table.insert(edges[from], landed)
					end
				end
			end
		end
		if recorded then
			local first = atlas.stops[1].path
			local seen: { [string]: boolean } = { [first] = true }
			local queue: { string } = { first }
			local head = 1
			while queue[head] do
				local at = queue[head]
				head += 1
				local targets: { string } = edges[at] or {}
				for _, target in targets do
					if not seen[target] then
						seen[target] = true
						table.insert(queue, target)
					end
				end
			end
			for _, stop in atlas.stops do
				if not seen[stop.path] then
					table.insert(problems, `unreachable: {stop.path}`)
				end
			end
		end
		table.sort(problems)
		return problems
	end

	for _, file in fs.readDir(DIR) do
		if string.sub(file, -5) ~= ".json" or string.find(file, "--keys.json", 1, true) then
			continue
		end
		local atlas = load(file)
		verifyHarness:suite(`focus walk {file}`, function()
			verifyHarness:case("the engine reaches every stop, and each recorded move lands on a known stop", {
				id = "native_focus_walk::"
					.. `focus walk {file}`
					.. "::the engine reaches every stop, and each recorded move lands on a known stop",
				run = function()
					local found = problemsOf(atlas)
					local report = process.env.FACET_FOCUS_WALK_REPORT
					if report and #found > 0 then
						fs.writeFile(`{report}/{file}`, serde.encode("json", { page = atlas.page, problems = found }))
					end
					Verify.expect(found):toEqual({})
				end,
			})
		end)
	end
end
