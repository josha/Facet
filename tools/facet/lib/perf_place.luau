--!strict

local Xml = require("./xml")

export type Entry = { class: string, source: string }

export type Tree = { [string]: Entry }

export type Requirement = { path: string, class: string }

export type Marker = { path: string, marker: string }

local Place = {}

Place.PROJECT = "examples/performance.project.json"
Place.BUILT = "artifacts/verify/native/performance.rbxl"
Place.ARTIFACT = "artifacts/performance-stress-places/place.json"
Place.LAB = "examples/performance/lab"
Place.MINIMUM_BYTES = 200000

Place.REQUIRED = {
	{ path = "ReplicatedStorage/Facet", class = "ModuleScript" },
	{ path = "ReplicatedStorage/Facet/ui", class = "ModuleScript" },
	{ path = "ReplicatedStorage/Facet/vendor/compose/core", class = "ModuleScript" },
	{ path = "ReplicatedStorage/Facet/vendor/compose/roblox", class = "ModuleScript" },
	{ path = "ReplicatedStorage/FacetScenarios", class = "ModuleScript" },
	{ path = "ReplicatedStorage/FacetScenarios/perf_lab", class = "ModuleScript" },
	{ path = "ReplicatedStorage/FacetScenarios/workloads", class = "ModuleScript" },
	{ path = "ReplicatedStorage/FacetScenarios/motion_workloads", class = "ModuleScript" },
	{ path = "ReplicatedStorage/FacetScenarios/dataset", class = "ModuleScript" },
	{ path = "ReplicatedStorage/FacetScenarios/rows", class = "ModuleScript" },
	{ path = "ReplicatedStorage/FacetScenarios/capture", class = "ModuleScript" },
	{ path = "ReplicatedStorage/FacetScenarios/sensory", class = "ModuleScript" },
	{ path = "ReplicatedStorage/PerfLab", class = "Script" },
	{ path = "Workspace/Baseplate", class = "Part" },
	{ path = "Workspace/SpawnLocation", class = "SpawnLocation" },
} :: { Requirement }

Place.VERSION_MARKERS = {
	{ path = "ReplicatedStorage/FacetScenarios/dataset", marker = 'dataset.VERSION = "perf-dataset/' },
	{ path = "ReplicatedStorage/FacetScenarios/rows", marker = 'VERSION = "native-perf-rows/' },
	{ path = "ReplicatedStorage/FacetScenarios/perf_lab", marker = 'lab.VERSION = "native-performance-lab/' },
	{ path = "ReplicatedStorage/FacetScenarios/capture", marker = 'capture.SCHEMA = "facet-perf-capture/' },
	{ path = "ReplicatedStorage/FacetScenarios/workloads", marker = 'workloads.VERSION = "native-perf-workloads/' },
} :: { Marker }

Place.SHARED_WITH_BENCH = { "workloads", "motion_workloads", "dataset", "rows" }

Place.FORBIDDEN = {
	{ needle = "/Users/", why = "an absolute developer filesystem path" },
	{ needle = "game.PlaceId =", why = "an assigned PlaceId" },
	{ needle = "game.GameId =", why = "an assigned GameId" },
	{ needle = "plugin:", why = "a plugin dependency (the place must run without one)" },
}

local function property(item: Xml.Element, kind: string, name: string): string?
	for _, properties in Xml.children(item, "Properties") do
		for _, value in Xml.children(properties, kind) do
			if value.attributes.name == name then
				return value.text
			end
		end
	end
	return nil
end

function Place.trim(text: string): string
	local first = string.find(text, "%S")
	if first == nil then
		return ""
	end
	local last = #text
	while last > first and string.find(string.sub(text, last, last), "^%s$") ~= nil do
		last -= 1
	end
	return string.sub(text, first, last)
end

function Place.index(root: Xml.Element): (Tree, { string })
	local tree: Tree = {}
	local order: { string } = {}
	local function walk(node: Xml.Element, prefix: string)
		for _, item in Xml.children(node, "Item") do
			local name = property(item, "string", "Name") or ""
			local path = string.gsub(prefix .. "/" .. name, "^/+", "")
			local source = property(item, "ProtectedString", "Source") or property(item, "string", "Source") or ""
			if tree[path] == nil then
				table.insert(order, path)
			end
			tree[path] = { class = item.attributes.class or "", source = source }
			walk(item, path)
		end
	end
	walk(root, "")
	return tree, order
end

function Place.inspectTree(tree: Tree, order: { string }, labSource: (string) -> string?): ({ string }, { string })
	local problems: { string } = {}
	local notes: { string } = {}
	for _, required in Place.REQUIRED do
		local found = tree[required.path]
		if found == nil then
			table.insert(problems, ("the built place has no %s"):format(required.path))
		elseif found.class ~= required.class then
			table.insert(problems, ("%s is a %s, expected %s"):format(required.path, found.class, required.class))
		end
	end
	for _, marker in Place.VERSION_MARKERS do
		local found = tree[marker.path]
		if found ~= nil and string.find(found.source, marker.marker, 1, true) == nil then
			table.insert(problems, ("%s does not carry the version marker '%s'"):format(marker.path, marker.marker))
		end
	end
	for _, module in Place.SHARED_WITH_BENCH do
		local found = tree["ReplicatedStorage/FacetScenarios/" .. module]
		local source = labSource(module)
		if found == nil or source == nil or Place.trim(found.source) ~= Place.trim(source) then
			table.insert(
				problems,
				("FacetScenarios/%s differs from %s/%s.luau - the place and the headless bench must run the same workload"):format(
					module,
					Place.LAB,
					module
				)
			)
		end
	end
	table.insert(
		notes,
		("%d workload modules are byte-identical to the headless bench source"):format(#Place.SHARED_WITH_BENCH)
	)
	local sources: { string } = {}
	for _, path in order do
		table.insert(sources, tree[path].source)
	end
	local joined = table.concat(sources, "\n")
	for _, forbidden in Place.FORBIDDEN do
		if string.find(joined, forbidden.needle, 1, true) ~= nil then
			table.insert(
				problems,
				("the built place source contains '%s' - %s"):format(forbidden.needle, forbidden.why)
			)
		end
	end
	return problems, notes
end

function Place.inspectBuilt(path: string, size: number?, magic: string?): ({ string }, { string })
	local problems: { string } = {}
	local notes: { string } = {}
	if size == nil or magic == nil then
		table.insert(problems, ("missing built place %s"):format(path))
		return problems, notes
	end
	if magic ~= "<roblox!" then
		table.insert(problems, ("%s is not a Roblox binary place (magic %q)"):format(path, magic))
	end
	if size < Place.MINIMUM_BYTES then
		table.insert(problems, ("%s is only %d bytes - the library alone is larger than that"):format(path, size))
	end
	table.insert(notes, ("%s: %d bytes, binary place"):format(path, size))
	return problems, notes
end

return table.freeze(Place)
