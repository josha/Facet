--!strict
local Verify = require("../../vendor/verify/src/core")

local Files = require("./files")
local Json = require("./json")
local Rule = require("./rule")

local LabBoundary = {}

LabBoundary.LAB = "examples/facet-lab"

local function isAbsolute(value: string): boolean
	local normalized = Files.normalize(value)
	return string.sub(normalized, 1, 1) == "/" or string.match(normalized, "^%a:/") ~= nil
end

local function resolve(base: string, value: string): string
	if isAbsolute(value) then
		return Files.absolute(value)
	end
	return Files.absolute(Files.join(base, value))
end

local function sources(node: unknown, found: { unknown })
	local object = Json.asObject(node)
	if object == nil then
		return
	end
	local mapped = object["$path"]
	if mapped ~= nil then
		table.insert(found, mapped)
	end
	for _, key in Json.keys(object) do
		if string.sub(key, 1, 1) ~= "$" then
			sources(object[key], found)
		end
	end
end

local function projects(lab: string): { string }
	local names: { string } = {}
	for _, entry in Files.list(lab) do
		if entry.type ~= "dir" and string.sub(entry.name, -13) == ".project.json" then
			table.insert(names, entry.name)
		end
	end
	table.sort(names)
	return names
end

function LabBoundary.check(root: string, outputs: { string }): { string }
	local facet = Files.absolute(root)
	local lab = Files.join(facet, LabBoundary.LAB)
	local problems: { string } = {}
	for _, name in projects(lab) do
		local project, problem = Json.tryDecode(Files.read(Files.join(lab, name)))
		if problem ~= nil then
			table.insert(problems, `{name}: cannot read the project: {problem}`)
			continue
		end
		local found: { unknown } = {}
		sources(Json.field(project, "tree"), found)
		for _, mapped in found do
			if type(mapped) ~= "string" then
				table.insert(problems, `{name}: source {Json.encode(mapped)} must exist inside Facet`)
				continue
			end
			local target = resolve(lab, mapped)
			if not Files.within(target, facet) or not Files.exists(target) then
				table.insert(problems, `{name}: source {mapped} must exist inside Facet`)
			end
		end
	end
	local build = Files.join(lab, "build")
	for _, output in outputs do
		if not Files.within(resolve(lab, output), build) then
			table.insert(problems, `output {output} is outside the lab build directory`)
		end
	end
	return problems
end

local function project(paths: { [string]: string }): string
	local tree = Json.object()
	Json.set(tree, "$className", "DataModel")
	for name, mapped in paths do
		local node = Json.object()
		Json.set(node, "$path", mapped)
		Json.set(tree, name, node)
	end
	return Json.encode({ name = "Lab", tree = tree })
end

function LabBoundary.register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "sources inside Facet and outputs in the lab build directory pass", {
		id = prefix .. "sources inside Facet and outputs in the lab build directory pass",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["src/init.luau"] = "return {}",
				["examples/facet-lab/src/init.luau"] = "return {}",
				["examples/facet-lab/default.project.json"] = project({ Facet = "../../src", Lab = "src" }),
			}, function(context: Rule.Context): ()
				Verify.expect(LabBoundary.check(context.root, { "build/Facet-Lab.rbxl" })):toEqual({})
			end)
		end,
	})
	harness:case(prefix .. "a source outside Facet and a missing source are refused", {
		id = prefix .. "a source outside Facet and a missing source are refused",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["src/init.luau"] = "return {}",
				["examples/facet-lab/theme-light.project.json"] = project({
					Outside = "../../../outside",
					Missing = "../../src/missing.luau",
				}),
			}, function(context: Rule.Context): ()
				local problems = LabBoundary.check(context.root, {})
				Verify.expect(#problems):toBe(2)
				Verify.expect(
					Rule.contains(problems, "theme-light.project.json: source ../../../outside must exist inside Facet")
				)
					:toBeTrueWith("the outside source was accepted: " .. Rule.describe(problems))
				Verify.expect(Rule.contains(problems, "source ../../src/missing.luau must exist inside Facet"))
					:toBeTrueWith("the missing source was accepted: " .. Rule.describe(problems))
			end)
		end,
	})
	harness:case(prefix .. "an output outside the lab build directory is refused", {
		id = prefix .. "an output outside the lab build directory is refused",
		run = function(test: Verify.Context)
			Rule.within(test, {
				["examples/facet-lab/default.project.json"] = project({}),
			}, function(context: Rule.Context): ()
				Verify.expect(LabBoundary.check(context.root, { "build/Facet-Lab.rbxl", "../build/Facet-Lab.rbxl" }))
					:toEqual({ "output ../build/Facet-Lab.rbxl is outside the lab build directory" })
			end)
		end,
	})
end

return table.freeze(LabBoundary)
