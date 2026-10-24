--!strict
local Verify = require("../../vendor/verify/src/core")

local Files = require("../lib/files")
local Rule = require("../lib/rule")
local ScenarioRequires = require("../lib/scenario_requires")

local fileSystem: ScenarioRequires.FileSystem = {
	isFile = Files.isFile,
	isDir = Files.isDirectory,
	readDir = function(path: string): { string }
		local names: { string } = {}
		for _, entry in Files.list(path) do
			table.insert(names, entry.name)
		end
		return names
	end,
	readFile = Files.read,
}

local function inspect(context: Rule.Context, options: ScenarioRequires.Options?): ScenarioRequires.Result
	return ScenarioRequires.check(fileSystem, context.root, options)
end

local function check(context: Rule.Context): { string }
	local findings: { string } = {}
	for _, violation in inspect(context).violations do
		table.insert(findings, ScenarioRequires.describe(violation))
	end
	return findings
end

local SCENARIO = "examples/gallery/scenarios/adaptive_controls.luau"

local function fixture(): { [string]: string }
	return {
		["src/init.luau"] = "return {}\n",
		["src/tokens/chrome_slots.luau"] = "return {}\n",
		["tools/vendor/verify/src/core.luau"] = "return {}\n",
		["examples/themes/noir.luau"] = "return {}\n",
		["examples/gallery/scenarios/init.luau"] = 'local common = require("@self/common")\nreturn common\n',
		["examples/gallery/scenarios/common.luau"] = "return {}\n",
		[SCENARIO] = 'local common = require("./common")\nlocal Facet = require("../Facet")\nreturn common\n',
		["examples/gallery/scenarios/adaptive_controls.verify.luau"] = 'local missing = require("./missing")\n',
		["examples/gallery/examples/01_basic.luau"] = 'local theme = require("../FacetThemes/noir")\nreturn theme\n',
		["examples/gallery/client/init.client.luau"] = 'local scenarios = require("./FacetScenarios")\n',
		["examples/gallery/server/main.server.luau"] = "return nil\n",
		["examples/reference/p1_glade/init.luau"] = 'local verify = require("../FacetVerify/core")\nreturn verify\n',
		["tools/studio/live/init.luau"] = "return {}\n",
		["examples/consumer/src/screen.luau"] = 'local live = require("./FacetLive")\nreturn live\n',
		["examples/virtual_monitors/monitor.luau"] = "return {}\n",
		["examples/virtual_monitors/monitor.client.luau"] = 'local missing = require("./missing")\n',
	}
end

local function within(test: Verify.Context, edit: (({ [string]: string }) -> ())?, body: (Rule.Context) -> ()): ()
	local files = fixture()
	if edit ~= nil then
		edit(files)
	end
	Rule.within(test, files, body)
end

local function register(harness: Verify.Harness, prefix: string): ()
	harness:case(prefix .. "the clean fixture passes and counts each relative module-scope require", {
		id = prefix .. "the clean fixture passes and counts each relative module-scope require",
		run = function(test: Verify.Context)
			within(test, nil, function(context)
				local result = inspect(context)
				Verify.expect(check(context)):toEqual({})
				Verify.expect(result.counts.files):toBe(12)
				Verify.expect(result.counts.requiresChecked):toBe(6)
			end)
		end,
	})
	harness:case(prefix .. "an injected line is scanned once per require", {
		id = prefix .. "an injected line is scanned once per require",
		run = function(test: Verify.Context)
			within(test, nil, function(context)
				local base = inspect(context).counts.requiresChecked
				local injected = inspect(context, {
					injectFile = SCENARIO,
					injectLine = 'local first = require("./common")\nlocal second = require("./common")',
				})
				Verify.expect(injected.counts.requiresChecked):toBe(base + 2)
				Verify.expect(injected.ok):toBeTrueWith("the injected requires resolve")
			end)
		end,
	})
	harness:case(prefix .. "a module-scope escape above the instance root is reported", {
		id = prefix .. "a module-scope escape above the instance root is reported",
		run = function(test: Verify.Context)
			within(test, nil, function(context)
				local result = inspect(context, {
					injectFile = SCENARIO,
					injectLine = 'local mutationProbe = require("../../../src/tokens/chrome_slots")',
				})
				local found = false
				for _, violation in result.violations do
					if violation.file == SCENARIO and violation.require == "../../../src/tokens/chrome_slots" then
						found = string.find(violation.reason, "could not get parent", 1, true) ~= nil
					end
				end
				Verify.expect(not result.ok and found):toBeTrueWith("the escape was not reported")
			end)
		end,
	})
	harness:case(prefix .. "a relative require to a missing instance is reported", {
		id = prefix .. "a relative require to a missing instance is reported",
		run = function(test: Verify.Context)
			within(test, function(files)
				files[SCENARIO] = 'local gone = require("./gone")\nreturn gone\n'
			end, function(context)
				Verify.expect(check(context)):toEqual({
					SCENARIO
						.. " (ReplicatedStorage.FacetScenarios.adaptive_controls): require(\"./gone\") \u{2014} resolves to 'ReplicatedStorage.FacetScenarios.gone', which does not exist in the Studio instance tree",
				})
			end)
		end,
	})
	harness:case(prefix .. "the dual-route idiom inside a function is not reported", {
		id = prefix .. "the dual-route idiom inside a function is not reported",
		run = function(test: Verify.Context)
			within(test, nil, function(context)
				local result = inspect(context, {
					injectFile = SCENARIO,
					injectLine = 'local function mutationProbe()\n\tlocal ok, mod = pcall(function()\n\t\treturn require("../../../src/tokens/chrome_slots")\n\tend)\n\treturn ok and mod or nil\nend',
				})
				Verify.expect(result.ok):toBeTrueWith("the indented require was reported")
			end)
		end,
	})
	harness:case(prefix .. "a require with no relative path component is never flagged", {
		id = prefix .. "a require with no relative path component is never flagged",
		run = function(test: Verify.Context)
			within(test, nil, function(context)
				local result = inspect(context, {
					injectFile = SCENARIO,
					injectLine = 'local mutationProbe = require(game:GetService("ReplicatedStorage").Facet.tokens.chrome_slots)',
				})
				Verify.expect(result.ok):toBeTrueWith("a non-relative require was reported")
			end)
		end,
	})
	harness:case(prefix .. "CRLF line endings and a missing mapped file are handled", {
		id = prefix .. "CRLF line endings and a missing mapped file are handled",
		run = function(test: Verify.Context)
			within(test, function(files)
				files[SCENARIO] = 'local gone = require("./gone")\r\nreturn gone\r\n'
				files["examples/consumer/src/screen.luau"] = nil
			end, function(context)
				local findings = check(context)
				Verify.expect(
					#findings == 2
						and Rule.contains(findings, "which does not exist in the Studio instance tree")
						and Rule.contains(
							findings,
							"examples/consumer/src/screen.luau (ReplicatedStorage.FacetConsumerScreen)"
						)
				):toBeTrueWith("expected the dead require and the missing file, got " .. Rule.describe(findings))
			end)
		end,
	})
end

local rule: Rule.Rule = {
	name = "scenario-requires",
	summary = "Every module-scope relative require in the gallery, scenarios and reference apps resolves in the Studio tree.",
	check = check,
	register = register,
}

return rule
