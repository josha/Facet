--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Bdd = require("../../tools/vendor/verify/src/bdd")
local commands = require("../../tools/facet/commands")
local Loader = require("../lib/loader")
local Run = require("../../tools/facet/lib/run")
local Files = require("../../tools/facet/lib/files")
local Json = require("../../tools/facet/lib/json")
local Static = require("../../tools/facet/lib/static_findings")
local Analyzer = require("../../tools/facet/lib/analyzer")
local Lute = require("../../tools/vendor/verify/src/lute")
local ControlProps = require("../../tools/facet/lib/control_props")
local system = require("@std/system")
local process = require("@std/process")

return function(harness: Verify.Harness)
	local test = Bdd.create(harness)
	local describe, it, expect = test.describe, test.it, test.expect
	it("test workers can fill the CPU budget and respect memory and explicit limits", function()
		local Policy = require("../../tools/facet/lib/gate")
		local gibibyte = 1024 ^ 3
		expect(Policy.workerCount(3, 16 * gibibyte, 100)):toBe(3)
		expect(Policy.workerCount(4, 16 * gibibyte, 100)):toBe(4)
		expect(Policy.workerCount(1, 16 * gibibyte, 100)):toBe(1)
		expect(Policy.workerCount(16, 64 * gibibyte, 100)):toBe(8)
		expect(Policy.workerCount(16, 4 * gibibyte, 100)):toBe(1)
		expect(Policy.workerCount(16, 64 * gibibyte, 3)):toBe(3)
		expect(Policy.workerCount(3, 16 * gibibyte, 100, 4)):toBe(4)
		expect(Policy.workerCount(16, 4 * gibibyte, 100, 8)):toBe(1)
		local sources = { "native_fields", "native_collections", "container_transfer", "hud_timer" }
		local override = tonumber(process.env.FACET_TEST_WORKERS or "")
		expect(Policy.tests("host-worker-units", sources).workers):toBe(
			Policy.workerCount(system.threadCount(), system.totalMemory() * 1024 ^ 2, #sources, override)
		)
		for _, invalid in { 0, -1, 1.5, math.huge } do
			expect(function()
				Policy.workerCount(8, 16 * gibibyte, 100, invalid)
			end):toThrow("positive integer")
		end
	end)
	it("parallel map keeps input order, bounds concurrency and raises the earliest failure", function()
		local Parallel = require("../../tools/facet/lib/parallel")
		local task = require("@std/task")
		local active, peak = 0, 0
		local doubled = Parallel.map({ 5, 1, 4, 2, 3 }, 2, function(delay: number): number
			active += 1
			peak = math.max(peak, active)
			task.wait(delay * 0.01)
			active -= 1
			return delay * 2
		end)
		expect(doubled):toEqual({ 10, 2, 8, 4, 6 })
		expect(peak):toBe(2)
		expect(function()
			Parallel.map({ 1, 2, 3 }, 3, function(value: number): number
				task.wait((4 - value) * 0.01)
				error("failed " .. value, 0)
			end)
		end):toThrow("failed 1")
	end)
	it("the gate audits off-reference scenes and preserves reference timing", function()
		local Policy = require("../../tools/facet/lib/gate")
		for _, reference in { false, true } do
			local found = false
			for _, producer in Policy.draft(reference).producers do
				if producer.id == "perf" then
					found = true
					expect(producer.env):toEqual({ FACET_PERF_TIMING = tostring(reference) })
					expect(producer.argv):toEqual({ "lute", "run", "tools/facet", "perf", "run" })
					expect(producer.requires):toBe(nil)
				end
			end
			expect(found):toBe(true)
		end
	end)
	it("consumer type cache reuses only matching analyzer, definitions and configuration", function(_own, t)
		local sources: { [string]: string } = {
			["sample.luau"] = "--!strict\nlocal value: number = 1\n",
			["default.project.json"] = '{"tree":{"Shared":{"$path":"shared"}}}',
			["shared/model.luau"] = "return 1",
			["shared/default.project.json"] = '{"tree":{"External":{"$path":"../external"}}}',
			["external/model.luau"] = "return 1",
			["tools/typecheck/roblox.d.luau"] = "declare value: number",
			["tools/typecheck/roblox.lock.json"] = '{"analyzerVersion":"1.69.0"}',
			[".luaurc"] = '{"languageMode":"strict"}',
		}
		local version, available, analyses = "1.69.0", true, 0
		local function relative(file: string): string
			return Analyzer.relative(file, Files.cwd())
		end
		local fakeFiles = {
			absolute = Files.absolute,
			parent = Files.parent,
			normalize = Files.normalize,
			collapse = Files.collapse,
			cwd = Files.cwd,
			join = Files.join,
			walk = function(directory: string): { string }
				local found: { string } = {}
				local prefix = relative(directory) .. "/"
				for file in sources do
					if string.sub(file, 1, #prefix) == prefix then
						table.insert(found, string.sub(file, #prefix + 1))
					end
				end
				return found
			end,
			isFile = function(file: string): boolean
				return sources[relative(file)] ~= nil
			end,
			isDirectory = function(directory: string): boolean
				local prefix = relative(directory) .. "/"
				for file in sources do
					if string.sub(file, 1, #prefix) == prefix then
						return true
					end
				end
				return false
			end,
			read = function(file: string): string
				return (assert(sources[relative(file)], file))
			end,
			write = function(file: string, text: string)
				sources[file] = text
			end,
			temporaryDirectory = function(_: string): string
				return "scratch"
			end,
			remove = function(_: string) end,
		}
		local function capture(argv: { string }, _: Run.Options?): Run.Result
			if argv[2] == "--version" then
				return {
					ok = available,
					code = if available then 0 else 127,
					stdout = version .. "\n",
					stderr = "",
					timedOut = false,
				}
			end
			if argv[1] == "rojo" then
				sources[argv[#argv]] = "{}"
				return { ok = true, code = 0, stdout = "", stderr = "", timedOut = false }
			end
			analyses += 1
			return {
				ok = false,
				code = 1,
				stdout = `sample.luau(1,1): TypeError: planted-{analyses}`,
				stderr = "",
				timedOut = false,
			}
		end
		local fakeRun = { capture = capture }
		local requireHost = (require :: unknown) :: (string) -> unknown
		local loader = Lute.loader.new({
			hostPaths = {
				"tools/facet/lib/analyzer",
				"tools/facet/lib/definitions",
				"tools/facet/lib/files",
				"tools/facet/lib/hash",
				"tools/facet/lib/json",
				"tools/facet/lib/run",
			},
			requireHost = function(module: string): unknown
				if module == "tools/facet/lib/files" then
					return fakeFiles
				end
				if module == "tools/facet/lib/run" then
					return fakeRun
				end
				if module == "tools/facet/lib/definitions" then
					return {
						resolve = function(_: string, file: string): string
							return file
						end,
					}
				end
				return requireHost("../../" .. module)
			end,
		})
		local consumer = loader.require("tools/facet/lib/consumer_types.luau") :: {
			check: ({ string }, string, string) -> ({ Analyzer.Diagnostic }?, string?),
		}
		local function checked(): { Analyzer.Diagnostic }
			local diagnostics, problem = consumer.check({ "sample.luau" }, "default.project.json", "new")
			t:expect(problem):toBe(nil)
			return assert(diagnostics)
		end
		t:expect(checked()[1].message):toBe("planted-1")
		t:expect(checked()[1].message):toBe("planted-1")
		t:expect(analyses):toBe(1)
		version = "1.68.0"
		local mismatch, problem = consumer.check({ "sample.luau" }, "default.project.json", "new")
		t:expect(mismatch):toBe(nil)
		t:expect(string.find(problem or "", "differs from the pinned toolchain", 1, true) ~= nil):toBe(true)
		available = false
		local missing, unavailable = consumer.check({ "sample.luau" }, "default.project.json", "new")
		t:expect(missing):toBe(nil)
		t:expect(string.find(unavailable or "", "missing", 1, true) ~= nil):toBe(true)
		t:expect(analyses):toBe(1)
		available, version = true, "1.69.0"
		sources["tools/typecheck/roblox.d.luau"] = "declare value: string"
		t:expect(checked()[1].message):toBe("planted-2")
		sources[".luaurc"] = '{"languageMode":"nonstrict"}'
		t:expect(checked()[1].message):toBe("planted-3")
		version = "1.70.0"
		sources["tools/typecheck/roblox.lock.json"] = '{"analyzerVersion":"1.70.0"}'
		t:expect(checked()[1].message):toBe("planted-4")
		t:expect(checked()[1].message):toBe("planted-4")
		t:expect(analyses):toBe(4)
		sources["shared/model.luau"] = "return 'changed'"
		t:expect(checked()[1].message):toBe("planted-5")
		sources["external/model.luau"] = "return 'nested mapping changed'"
		t:expect(checked()[1].message):toBe("planted-6")
		sources["ui/sample.luau"] = sources["sample.luau"]
		local function standalone(): { Analyzer.Diagnostic }
			local diagnostics, failure = consumer.check({ "ui/sample.luau" }, "default.project.json", "new")
			t:expect(failure):toBe(nil)
			return assert(diagnostics)
		end
		standalone()
		t:expect(analyses):toBe(7)
		sources["ui/.luaurc"] = '{"languageMode":"strict"}'
		standalone()
		t:expect(analyses):toBe(8)
		sources["ui/.luaurc"] = '{"languageMode":"nonstrict"}'
		standalone()
		t:expect(analyses):toBe(9)
		standalone()
		t:expect(analyses):toBe(9)
	end)
	it("author replay counts a requested saved report without running a project", function(_own, t)
		local root = Files.temporaryDirectory("facet-author-replay")
		t:defer(function()
			Files.remove(root)
		end)
		local event = Json.encode({
			type = "item.completed",
			item = {
				type = "command_execution",
				command = "lute run tools/facet verify --static",
				aggregated_output = "warning [paint] Keep this advice (1 finding(s))\n    screen.luau:3\nerror [types] Available overloads: (StackProps) (2 finding(s))\n    screen.luau:1\n    screen.luau:2\nFull static findings: report.txt\n",
			},
		})
		Files.write(Files.join(root, "transcript.jsonl"), "0\t" .. event .. "\n")
		local text = "desktop 2-shop: high [text-fit] App.Shop: clipped\n"
		Files.write(Files.join(root, "workspace/artifacts/check/report.txt"), text)
		local result = Run.capture({
			Run.lute(),
			"run",
			"tools/facet",
			"author-replay",
			root,
			"--out",
			Files.join(root, "replay"),
			"--report",
			"artifacts/check/report.txt",
		})
		t:expect(result.ok):toBe(true)
		t:expect(string.find(result.stdout, `reports (1, first failing group page): {#text} ->`, 1, true) ~= nil)
			:toBe(true)
		t:expect(Files.read(Files.join(root, "workspace/artifacts/check/report.txt"))):toBe(text)
		local static = Files.read(Files.join(root, "replay/static-after.txt"))
		t:expect(string.find(static, "screen.luau:1", 1, true) ~= nil):toBe(true)
		t:expect(string.find(static, "screen.luau:2", 1, true) ~= nil):toBe(true)
		t:expect(string.find(static, "docs Stack.props", 1, true) ~= nil):toBe(true)
		t:expect(string.find(static, "Keep this advice", 1, true) ~= nil):toBe(true)
	end)
	it("short type diagnostics point to typed options and retain the complete input finding", function(_own, t)
		local finding: Static.Finding = {
			severity = "error",
			rule = "types",
			message = "Available overloads: (StackProps) " .. string.rep("large type ", 80),
			location = "screen.luau:10",
		}
		local output = table.concat(Static.render({ finding }), "\n")
		t:expect(string.find(output, "lute run tools/facet docs Stack.props", 1, true) ~= nil):toBe(true)
		t:expect(#output < 400):toBe(true)
		t:expect(#finding.message > 800):toBe(true)
	end)
	it("verify rejects a Sheet captured before it enters the viewport", function(_own, t)
		local Look = require("../../tools/facet/lib/look")
		local dump = Look.decode(Look.sample(false))
		local panel = dump.elements[1]
		panel.path = "PlayerGui.Sample.Modal.SheetPanel"
		panel.selectionGroup = true
		t:expect(#Look.presentationProblems(dump)):toBe(0)
		panel.rect.y = dump.screen.height
		t:expect(#Look.presentationProblems(dump)):toBe(1)
		local found = false
		for _, finding in Look.audit(dump, "desktop").violations do
			found = found or finding.rule == "modal-presentation"
		end
		t:expect(found):toBe(true)
	end)
	it("audit reports a HUD zone that moved under a corner into the play view", function(_own, t)
		local Look = require("../../tools/facet/lib/look")
		local dump = Look.decode(Look.sample(false))
		local template = dump.elements[1]
		local function zone(name: string, x: number, y: number, width: number, height: number)
			local element = table.clone(template)
			element.path = "PlayerGui.Sample.Hud.Zones." .. name
			element.rect = { x = x, y = y, width = width, height = height }
			element.visible = true
			table.insert(dump.elements, element)
			return element
		end
		local function covered(): number
			local count = 0
			for _, finding in Look.audit(dump, "phone-portrait").violations do
				if finding.rule == "hud-in-view" then
					count += 1
				end
			end
			return count
		end
		zone("TopLeft", 8, 8, 103, 102)
		local top = zone("Top", 40, 118, 308, 27)
		t:expect(covered()):toBe(1)
		top.rect = { x = 160, y = 8, width = 180, height = 27 }
		t:expect(covered()):toBe(0)
		top.rect = { x = 40, y = 118, width = 0, height = 0 }
		t:expect(covered()):toBe(0)
		zone("BottomRight", 311, 626, 70, 70)
		zone("Bottom", 40, 548, 300, 40)
		t:expect(covered()):toBe(1)
	end)
	it("static output groups by rule message and hint and bounds locations", function(_own, t)
		local findings: { Static.Finding } = {}
		for index = 1, 8 do
			local finding: Static.Finding = {
				rule = "types",
				severity = "error",
				message = "Wrong width",
				hint = "Use Size",
				location = `a.luau:{index}`,
			}
			table.insert(findings, finding)
		end
		local last: Static.Finding =
			{ rule = "types", severity = "error", message = "Wrong width", hint = "Use fill", location = "b.luau:1" }
		table.insert(findings, last)
		local text = table.concat(Static.render(findings), "\n")
		local _, messages = string.gsub(text, "Wrong width", "")
		t:expect(messages):toBe(2)
		t:expect(string.find(text, "(8 finding(s))", 1, true) ~= nil):toBe(true)
		t:expect(string.find(text, "and 3 more", 1, true) ~= nil):toBe(true)
		t:expect((string.find(text, "a.luau:6", 1, true))):toBe(nil)
		t:expect(#findings):toBe(9)
		for _, option in { "width", "height", "gap", "padding", "align", "distribute", "maxWidth" } do
			t:expect(Static.layoutHint(option) ~= nil):toBe(true)
		end
		t:expect(Static.layoutHint("unknown")):toBe(nil)
	end)
	it("live static warnings print counts and a report path without advice or locations", function(_own, t)
		local warning: Static.Finding =
			{ rule = "raw-input", severity = "warning", message = "Advice", location = "a:1" }
		local result = table.concat(Static.render({ warning, warning }, true), "\n")
		t:expect(result):toBe("warning [raw-input] 2 finding(s); read artifacts/facet-lint/report.txt")
		t:expect(string.find(table.concat(Static.render({ warning }), "\n"), "Advice", 1, true) ~= nil):toBe(true)
	end)
	it("only stack cascades explained by nested child option errors are hidden", function(_own, t)
		local source = 'UI.VStack({\n UI.Text { width = "fill" },\n}, "Rows")\nUI.VStack { gap = false }'
		local function diagnostic(line: number, column: number, message: string): Analyzer.Diagnostic
			return { file = "a.luau", line = line, column = column, kind = "TypeError", message = message }
		end
		local diagnostics = {
			diagnostic(1, 1, "None of the overloads for function"),
			diagnostic(1, 1, "Available overloads: (StackProps) -> Frame"),
			diagnostic(2, 12, "Expected this to be 'number', but got '\"width\"'"),
			diagnostic(4, 1, "None of the overloads for function"),
			diagnostic(4, 1, "Available overloads: (StackProps) -> Frame"),
		}
		local hidden = Static.cascades(diagnostics, { ["a.luau"] = source })
		t:expect(hidden[1]):toBe(true)
		t:expect(hidden[2]):toBe(true)
		t:expect(hidden[3]):toBe(nil)
		t:expect(hidden[4]):toBe(nil)
		t:expect(hidden[5]):toBe(nil)
		t:expect(#diagnostics):toBe(5)
		for _, diagnostic in diagnostics do
			diagnostic.file = "c:/project/a.luau"
		end
		t:expect(Static.cascades(diagnostics, { ["C:/Project/a.luau"] = source })[1]):toBe(true)
		for _, diagnostic in diagnostics do
			diagnostic.file = "a.luau"
		end
		diagnostics[3].file = "other.luau"
		t:expect((next(Static.cascades(diagnostics, { ["a.luau"] = source })))):toBe(nil)
	end)
	it("first docs call contains the small task map and recoverable node discovery", function()
		local first = Run.capture({ Run.lute(), "run", "tools/facet", "docs" })
		expect(first.ok):toBe(true)
		expect(#first.stdout <= 2048):toBe(true)
		for _, text in
			{
				"Tasks.collection-detail",
				"Tasks.sheet",
				"Controls",
				"Themes.index",
				"Tasks.pages",
				"ServerStorage.FacetDocs",
				"<Control>.card",
				"<Control>.props",
			}
		do
			expect(string.find(first.stdout, text, 1, true) ~= nil):toBe(true)
		end
		local theme = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "Theme packages" })
		expect(theme.ok):toBe(true)
		expect(string.find(theme.stdout, "Resolved 'Theme packages' to Tasks.theme.", 1, true) ~= nil):toBe(true)
		local layout = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "Sizing and layout" })
		expect(layout.ok):toBe(true)
		expect(string.find(layout.stdout, "Open one path", 1, true) ~= nil):toBe(true)
	end)
	it(
		"verify accepts BOM and mixed public reactive types and audits saved evidence without Studio",
		function(_own, context)
			local directory = Files.temporaryDirectory("facet-verify-consumer")
			context:defer(function()
				Files.remove(directory)
			end)
			local source = Files.join(directory, "main.client.luau")
			local project = Files.join(directory, "default.project.json")
			local dump = Files.join(directory, "dump.json")
			local text = [=[--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app()
local UI = app.UI
local Host = Facet.host(app.runtime)
local UserInputService = game:GetService("UserInputService")
UserInputService.InputBegan:Connect(function() end)
UserInputService.InputBegan:Connect(function() end)
type Entry = { id: string, title: string }
local initial: { Entry } = {}
local entries = Compose.cell(initial)
local busy = Compose.cell(false)
local initialBalances: { [string]: number } = { Credits = 0 }
local balances = Compose.cell(initialBalances)
local key = Compose.cell("Credits")
app.mount(function()
        UI.VStack "Width" { width = "fill", align = "stretch", UI.Text "Child" { text = "Ready",} }
        UI.HStack "Height" { height = 64, align = "stretch", UI.Text "Child" { text = "Ready",} }
        UI.HStack "GrowWidth" { width = "fill", UI.Text "Child" { text = "Ready", UI.fill() } }
        UI.VStack "GrowHeight" { height = "fill", UI.Text "Child" { text = "Ready", UI.fill() } }
        UI.Text "NativeWidth" { text = "Ready", Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }
        UI.Text "NativeHeight" { text = "Ready", Size = UDim2.fromOffset(0, 48), AutomaticSize = Enum.AutomaticSize.X }
        UI.Text "Fixed" { text = "Ready", Size = UDim2.fromOffset(160, 48), AutomaticSize = Enum.AutomaticSize.None }
        UI.VStack "ContainerOptions" { gap = "s", padding = "m", align = "center", distribute = "start", maxWidth = 480, UI.Text "Child" { text = "Ready",} }
        UI.Text "NativePadding" { text = "Ready", Host.UIPadding { PaddingLeft = UDim.new(0, 8) } }
        UI.Text "NativeLimit" { text = "Ready", Host.UISizeConstraint { MaxSize = Vector2.new(480, math.huge) } }
        UI.VStack "Width" { width = "fill", align = "stretch", UI.Button "Child" {} }
        UI.HStack "Height" { height = 64, align = "stretch", UI.Button "Child" {} }
        UI.HStack "GrowWidth" { width = "fill", UI.Button "Child" { UI.fill() } }
        UI.VStack "GrowHeight" { height = "fill", UI.Button "Child" { UI.fill() } }
        UI.Button "NativeWidth" { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y }
        UI.Button "NativeHeight" { Size = UDim2.fromOffset(0, 48), AutomaticSize = Enum.AutomaticSize.X }
        UI.Button "Fixed" { Size = UDim2.fromOffset(160, 48), AutomaticSize = Enum.AutomaticSize.None }
        UI.VStack "ContainerOptions" { gap = "s", padding = "m", align = "center", distribute = "start", maxWidth = 480, UI.Button "Child" {} }
        UI.Button "NativePadding" { Host.UIPadding { PaddingLeft = UDim.new(0, 8) } }
        UI.Button "NativeLimit" { Host.UISizeConstraint { MaxSize = Vector2.new(480, math.huge) } }
    local spec: Facet.KeyedCollectionSpec<Entry, string> = {
        from = entries, key = "id", itemSize = 64,
        render = function(current)
            return UI.Button "Entry" {
                label = function(use: Facet.Use)
                    return use(current).title .. tostring(use(balances)[use(key)] or 0)
                end,
                enabled = function(use: Facet.Use) return not use(busy) end,
            }
        end,
    }
    return UI.Screen "Root" { UI.VirtualList "Entries" (spec) }
end)
]=]
			Files.write(source, "\239\187\191" .. text)
			Files.write(
				project,
				Json.encode({
					name = "Consumer",
					tree = {
						["$className"] = "DataModel",
						ReplicatedStorage = {
							Packages = {
								["$className"] = "Folder",
								Facet = { ["$path"] = Files.join(Files.cwd(), "src") },
							},
						},
						StarterPlayer = { StarterPlayerScripts = { Main = { ["$path"] = source } } },
					},
				})
			)
			local Look = require("../../tools/facet/lib/look")
			Files.write(dump, Look.sample(false))
			local command = {
				Run.lute(),
				"run",
				"tools/facet",
				"verify",
				source,
				"--project",
				project,
				"--out",
				Files.join(directory, "out"),
				"--static",
			}
			local static = Run.capture(command)
			expect(static.ok):toBeTrueWith(static.stdout .. static.stderr)
			expect(Files.read(source)):toBe(text)
			expect(string.find(static.stdout, "not checked (--static)", 1, true) ~= nil):toBeTrueWith(static.stdout)
			expect(string.find(static.stdout, "facet lint:", 1, true) == nil):toBeTrueWith(static.stdout)
			expect(string.find(static.stdout, "verify: PASS", 1, true) ~= nil):toBeTrueWith(static.stdout)
			expect(string.find(static.stdout, "Let controls own activation", 1, true) ~= nil):toBeTrueWith(
				static.stdout
			)
			table.remove(command)
			for _, argument in { "--dump", dump, "--device", "desktop" } do
				table.insert(command, argument)
			end
			local saved = Run.capture(command)
			expect(string.find(saved.stdout, "saved evidence only", 1, true) ~= nil):toBeTrueWith(saved.stdout)
			expect(
				string.find(
					saved.stdout,
					"warning [raw-input] 2 finding(s); read artifacts/facet-lint/report.txt",
					1,
					true
				) ~= nil
			):toBeTrueWith(saved.stdout)
			expect({
				output = "saved",
				found = string.find(saved.stdout, "Let controls own activation", 1, true),
			}):toEqual({ output = "saved" })
			Files.write(dump, Look.sample(true))
			local weak = Run.capture(command)
			expect(not weak.ok):toBeTrueWith(weak.stdout)
			expect(string.find(weak.stdout, "verify: FAIL", 1, true) ~= nil):toBeTrueWith(weak.stdout)
			expect(string.find(weak.stdout, "[text-truncated]", 1, true) ~= nil):toBeTrueWith(weak.stdout)
			expect({ output = "weak", found = string.find(weak.stdout, "Let controls own activation", 1, true) }):toEqual({
				output = "weak",
			})
			local children: { string } = {}
			for index = 1, 8 do
				table.insert(children, ('UI.Text { Name = "Bad%d", text = 1 },'):format(index))
			end
			Files.write(
				source,
				text .. "\napp.mount(function() return UI.VStack {\n" .. table.concat(children, "\n") .. "\n} end)\n"
			)
			local invalid =
				Run.capture({ Run.lute(), "run", "tools/facet", "lint", source, "--types", "--project", project })
			expect(not invalid.ok):toBeTrueWith(invalid.stdout .. invalid.stderr)
			expect(string.find(invalid.stdout, "and 3 more", 1, true) ~= nil):toBeTrueWith(invalid.stdout)
			expect({ output = "invalid", found = string.find(invalid.stdout, "Available overloads", 1, true) }):toEqual({
				output = "invalid",
			})
			expect({ output = "invalid", found = string.find(invalid.stdout, "None of the overloads", 1, true) }):toEqual({
				output = "invalid",
			})
			local report = Files.read("artifacts/facet-lint/report.txt")
			local _, widths = string.gsub(report, "error %[types%]", "")
			expect(widths):toBe(8)
			Files.write(source, text .. '\nUI.VirtualList(42, "BadList")\n')
			local overloaded =
				Run.capture({ Run.lute(), "run", "tools/facet", "lint", source, "--types", "--project", project })
			expect(overloaded.ok):toBe(false)
			local overloads = Files.read("artifacts/facet-lint/report.txt")
			expect(string.find(overloads, "error [types]", 1, true) ~= nil):toBeTrueWith(overloads)
		end
	)
	it("author docs bound broad reads and return paths for a batch", function()
		local compact = Run.capture({
			Run.lute(),
			"run",
			"tools/facet",
			"docs",
			"Screen",
			"Sheet",
			"VStack",
			"HStack",
			"Text",
			"Button",
			"VirtualGrid",
			"Card",
			"Notice",
			"Sheet and overlay focus",
			"Selection and gamepad focus",
			"Typed collections",
		})
		expect(compact.ok):toBe(true)
		expect(#compact.stdout <= 4096):toBe(true)
		expect(string.find(compact.stdout, "Open one path", 1, true) ~= nil):toBe(true)
		local full = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "VirtualList", "VirtualGrid", "--full" })
		expect(full.ok):toBe(true)
		local _, lists = string.gsub(full.stdout, "VirtualList.card %-", "")
		local _, grids = string.gsub(full.stdout, "VirtualGrid.card %-", "")
		expect(lists):toBe(1)
		expect(grids):toBe(1)
		expect(string.find(full.stdout, "```luau", 1, true) == nil):toBe(true)
		local card = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "VirtualGrid.card" })
		expect(card.ok):toBe(true)
		expect(string.find(card.stdout, "minColumnWidth", 1, true) ~= nil):toBe(true)
	end)
	it("author setup and task recipes fit a short first read", function()
		local info = Run.capture({ Run.lute(), "run", "tools/facet", "info" })
		expect(info.ok):toBe(true)
		expect(#info.stdout < 3200):toBe(true)
		local recipes = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "Tasks.collection-detail" })
		expect(recipes.ok):toBe(true)
		expect(#recipes.stdout <= 2048):toBe(true)
		expect(string.find(recipes.stdout, "Facet.ReadOnlyValue<Item>", 1, true) ~= nil):toBe(true)
	end)
	it("lint keeps all error locations and full details when it shortens cyclic type errors", function(_own, context)
		local temporary = Files.temporaryDirectory("facet-lint-output")
		local directory = Files.join("artifacts/verify", Files.name(temporary))
		Files.remove(temporary)
		context:defer(function()
			Files.remove(directory)
		end)
		local source = Files.join(directory, "fault.luau")
		local project = Files.join(directory, "default.project.json")
		Files.write(
			source,
			[=[--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local app = Facet.app()
local UI = app.UI
type Entry = { id: string, title: string }
local entries: { Entry } = {}
local initial: { name: string, enabled: boolean }? = nil
local state = Facet.Compose.cell(initial)
local wrong: Facet.ReadOnlyValue<Entry> = state
app.mount(function()
    local spec: Facet.KeyedCollectionSpec<Entry, string> = {
        from = Facet.Compose.cell(entries), key = "id", itemSize = 64,
        render = function(current)
            return UI.Text "Status" {
                text = function(use)
                    local entry, snapshot = use(current), use(state)
                    return if snapshot then snapshot.name .. entry.title else "Waiting"
                end,
            }
        end,
    }
    return UI.VirtualList "Entries" (spec)
end)
]=]
		)
		Files.write(
			project,
			Json.encode({
				name = "LintOutput",
				tree = {
					["$className"] = "DataModel",
					ReplicatedStorage = {
						Packages = {
							["$className"] = "Folder",
							Facet = { ["$path"] = Files.join(Files.cwd(), "src") },
						},
					},
					StarterPlayer = {
						StarterPlayerScripts = { Fault = { ["$path"] = Files.join(Files.cwd(), source) } },
					},
				},
			})
		)
		local argv = { Run.lute(), "run", "tools/facet", "lint", source, "--types", "--project", project }
		local compact = Run.capture(argv)
		table.insert(argv, "--verbose")
		local full = Run.capture(argv)
		expect(compact.ok):toBe(false)
		expect(full.ok):toBe(false)
		expect(string.find(compact.stdout, "function(use: Facet.Use)", 1, true) ~= nil):toBeTrueWith(
			compact.stdout .. compact.stderr
		)
		expect(string.find(compact.stdout, "[shortened]", 1, true) ~= nil):toBeTrueWith(
			compact.stdout .. compact.stderr
		)
		expect(#compact.stdout < #full.stdout):toBeTrueWith(
			`compact={#compact.stdout}, full={#full.stdout}\n{full.stdout}`
		)
		local report = Files.read("artifacts/facet-lint/report.txt")
		local _, reportLocations = string.gsub(report, ": error %[types%]", "")
		local _, fullLocations = string.gsub(full.stdout, ": error %[types%]", "")
		expect(reportLocations):toBe(fullLocations)
		expect(string.find(compact.stdout, "artifacts/facet-lint/report.txt", 1, true) ~= nil):toBeTrueWith(
			compact.stdout
		)
		expect(string.match(report, "t%d+ where t%d+ =") ~= nil):toBeTrueWith(report)
	end)
	it("the public surface checker detects removed, added and changed exports", function()
		local result = Run.capture({ Run.lute(), "run", "tools/engine/check_public_surface.luau", "--selftest" })
		expect(result.ok):toBe(true)
		expect(string.find(result.stdout, "SELFTEST PASS", 1, true) ~= nil):toBe(true)
	end)
	it("property origins use table syntax and refresh between scans", {
		id = "tools/commands::props::syntax and freshness",
		run = function(_own, context)
			local root = Files.temporaryDirectory("facet-prop-syntax")
			context:defer(function()
				Files.remove(root)
			end)
			local paths: { [string]: boolean } = { ["src/ui/engine_types.luau"] = true }
			for _, family in ControlProps.FAMILIES do
				for _, module in family.modules do
					paths["src/ui/" .. string.sub(module, 3) .. ".luau"] = true
				end
			end
			for path in paths do
				Files.copy(path, Files.join(root, path))
			end
			local path = Files.join(root, "src/ui/input_types.luau")
			local source = Files.text(path)
			local header = "export type EnabledOptions%s*=%s*{"
			local function withFields(fields: string): string
				return (
					string.gsub(source, header, function()
						return "export type EnabledOptions = {" .. fields
					end, 1)
				)
			end
			Files.write(
				path,
				withFields([[
	astProbe: <T>(value: { nestedProbe: T, labelProbe: "},<" }) -> (T, string);
	astOther: { [string]: { value: number } };
]])
			)
			local origins = ControlProps.optionOrigins(root)
			expect(origins.ButtonProps.astProbe):toBe("EnabledOptions")
			expect(origins.ButtonProps.astOther):toBe("EnabledOptions")
			expect(origins.ButtonProps.nestedProbe):toBe(nil)
			expect(origins.ButtonProps.labelProbe):toBe(nil)
			Files.write(path, withFields(" astReplacement: boolean;\n"))
			local refreshed = ControlProps.optionOrigins(root)
			expect(refreshed.ButtonProps.astProbe):toBe(nil)
			expect(refreshed.ButtonProps.astReplacement):toBe("EnabledOptions")
			expect(ControlProps.optionOrigins(".").ButtonProps.astReplacement):toBe(nil)
			for _, definition in { "{} & {}", "{} | {}", "string" } do
				local renamed = string.gsub(source, "export type EnabledOptions", "type OriginalEnabledOptions", 1)
				Files.write(path, "export type EnabledOptions = " .. definition .. "\n" .. renamed)
				local ok, problem = pcall(ControlProps.optionOrigins, root)
				expect(ok):toBe(false)
				expect(string.find(tostring(problem), "must be one table type", 1, true) ~= nil):toBe(true)
			end
		end,
	})
	it("module loader resolves an explicit Luau file before directory candidates", {
		id = "tools/commands::loader::explicit Luau file",
		run = function()
			local loader = Loader.new()
			local explicit = loader.require("src/ui/rich_text.luau")
			expect(loader.require("src/ui/rich_text")):toBe(explicit)
			expect(type(explicit)):toBe("table")
		end,
	})
	it("module loader reports a missing explicit Luau file", {
		id = "tools/commands::loader::missing Luau file",
		run = function()
			local ok, failure = pcall(Loader.new().require, "tests/lib/missing-macos-loader-fixture.luau")
			expect(ok):toBe(false)
			expect(string.find(tostring(failure), "no module at ", 1, true) ~= nil):toBe(true)
		end,
	})
	for _, command in commands do
		local register = command.register
		if register then
			describe(command.name, function()
				register(harness, "tools/commands::" .. command.name .. "::")
			end)
		end
	end
end
