--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local commands = require("../../tools/facet/commands")
local Loader = require("../lib/loader")
local Run = require("../../tools/facet/lib/run")
local Files = require("../../tools/facet/lib/files")
local Json = require("../../tools/facet/lib/json")
local Static = require("../../tools/facet/lib/static_findings")
local Analyzer = require("../../tools/facet/lib/analyzer")
local Lute = require("../../tools/vendor/verify/src/lute")

return function(harness: Verify.Harness)
	harness:case("the gate audits off-reference scenes and preserves reference timing", function()
		local Policy = require("../../tools/facet/lib/gate")
		for _, reference in { false, true } do
			local found = false
			for _, producer in Policy.draft(reference).producers do
				if producer.id == "perf" then
					found = true
					Verify.expect(producer.env):toEqual({ FACET_PERF_TIMING = tostring(reference) })
					Verify.expect(producer.argv):toEqual({ "lute", "run", "tools/facet", "perf", "run" })
					Verify.expect(producer.requires):toBe(nil)
				end
			end
			Verify.expect(found):toBe(true)
		end
	end)
	harness:case("consumer type cache reuses only matching analyzer, definitions and configuration", function(t)
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
	harness:case("author replay counts a requested saved report without running a project", function(t)
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
	harness:case("short type diagnostics point to typed options and retain the complete input finding", function(t)
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
	harness:case("verify rejects a Sheet captured before it enters the viewport", function(t)
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
	harness:case("static output groups by rule message and hint and bounds locations", function(t)
		local findings: { Static.Finding } = {}
		for index = 1, 8 do
			table.insert(findings, {
				rule = "types",
				severity = "error",
				message = "Wrong width",
				hint = "Use Size",
				location = `a.luau:{index}`,
			})
		end
		table.insert(
			findings,
			{ rule = "types", severity = "error", message = "Wrong width", hint = "Use fill", location = "b.luau:1" }
		)
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
	harness:case("live static warnings print counts and a report path without advice or locations", function(t)
		local warning: Static.Finding =
			{ rule = "raw-input", severity = "warning", message = "Advice", location = "a:1" }
		local result = table.concat(Static.render({ warning, warning }, true), "\n")
		t:expect(result):toBe("warning [raw-input] 2 finding(s); read artifacts/facet-lint/report.txt")
		t:expect(string.find(table.concat(Static.render({ warning }), "\n"), "Advice", 1, true) ~= nil):toBe(true)
	end)
	harness:case("only stack cascades explained by nested child option errors are hidden", function(t)
		local source = 'UI.VStack "Rows" {\n UI.Text { width = "fill" },\n}\nUI.VStack { gap = false }'
		local function diagnostic(line: number, column: number, message: string): Analyzer.Diagnostic
			return { file = "a.luau", line = line, column = column, kind = "TypeError", message = message }
		end
		local diagnostics = {
			diagnostic(1, 1, "None of the overloads for function"),
			diagnostic(1, 1, "Available overloads: (StackProps) -> Frame"),
			diagnostic(2, 12, "Expected this to be 'EventKey | number', but got '\"width\"'"),
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
	harness:case("first docs call contains the small task map and recoverable node discovery", function()
		local first = Run.capture({ Run.lute(), "run", "tools/facet", "docs" })
		Verify.expect(first.ok):toBe(true)
		Verify.expect(#first.stdout <= 2048):toBe(true)
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
			Verify.expect(string.find(first.stdout, text, 1, true) ~= nil):toBe(true)
		end
		local theme = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "Theme packages" })
		Verify.expect(theme.ok):toBe(true)
		Verify.expect(string.find(theme.stdout, "Resolved 'Theme packages' to Tasks.theme.", 1, true) ~= nil):toBe(true)
		local layout = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "Sizing and layout" })
		Verify.expect(layout.ok):toBe(true)
		Verify.expect(string.find(layout.stdout, "Open one path", 1, true) ~= nil):toBe(true)
	end)
	harness:case(
		"verify accepts BOM and mixed public reactive types and audits saved evidence without Studio",
		function(context)
			local directory = Files.temporaryDirectory("facet-verify-consumer")
			context:defer(function()
				Files.remove(directory)
			end)
			local source = Files.join(directory, "main.client.luau")
			local project = Files.join(directory, "default.project.json")
			local dump = Files.join(directory, "dump.json")
			local text = [[--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local Compose = Facet.Compose
local app = Facet.app()
local UI = app.UI
local Host = app.runtime.constructors
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
]]
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
			Verify.expect(static.ok):toBe(true)
			Verify.expect(Files.read(source)):toBe(text)
			Verify.expect(string.find(static.stdout, "not checked (--static)", 1, true) ~= nil):toBe(true)
			Verify.expect(string.find(static.stdout, "facet lint:", 1, true) == nil):toBe(true)
			Verify.expect(string.find(static.stdout, "verify: PASS", 1, true) ~= nil):toBe(true)
			Verify.expect(string.find(static.stdout, "Let controls own activation", 1, true) ~= nil):toBe(true)
			table.remove(command)
			for _, argument in { "--dump", dump, "--device", "desktop" } do
				table.insert(command, argument)
			end
			local saved = Run.capture(command)
			Verify.expect(string.find(saved.stdout, "saved evidence only", 1, true) ~= nil):toBe(true)
			Verify.expect(
				string.find(
					saved.stdout,
					"warning [raw-input] 2 finding(s); read artifacts/facet-lint/report.txt",
					1,
					true
				) ~= nil
			):toBe(true)
			Verify.expect({
				output = "saved",
				found = string.find(saved.stdout, "Let controls own activation", 1, true),
			}):toEqual({ output = "saved" })
			Files.write(dump, Look.sample(true))
			local weak = Run.capture(command)
			Verify.expect(weak.ok):toBe(false)
			Verify.expect(string.find(weak.stdout, "verify: FAIL", 1, true) ~= nil):toBe(true)
			Verify.expect(string.find(weak.stdout, "[text-truncated]", 1, true) ~= nil):toBe(true)
			Verify.expect({ output = "weak", found = string.find(weak.stdout, "Let controls own activation", 1, true) })
				:toEqual({ output = "weak" })
			local children: { string } = {}
			for index = 1, 8 do
				table.insert(children, ('UI.Text "Bad%d" { text = "Bad", width = "fill" },'):format(index))
			end
			Files.write(
				source,
				text .. "\napp.mount(function() return UI.VStack {\n" .. table.concat(children, "\n") .. "\n} end)\n"
			)
			local invalid =
				Run.capture({ Run.lute(), "run", "tools/facet", "lint", source, "--types", "--project", project })
			Verify.expect(invalid.ok):toBe(false)
			Verify.expect(string.find(invalid.stdout, "and 3 more", 1, true) ~= nil):toBe(true)
			Verify.expect({ output = "invalid", found = string.find(invalid.stdout, "Available overloads", 1, true) })
				:toEqual({ output = "invalid" })
			Verify.expect({ output = "invalid", found = string.find(invalid.stdout, "None of the overloads", 1, true) })
				:toEqual({ output = "invalid" })
			local report = Files.read("artifacts/facet-lint/report.txt")
			Verify.expect(string.find(report, "Available overloads", 1, true) ~= nil):toBe(true)
			Verify.expect(string.find(report, "None of the overloads", 1, true) ~= nil):toBe(true)
			local _, widths = string.gsub(report, "got '\"width\"'", "")
			Verify.expect(widths):toBe(8)
		end
	)
	harness:case("author docs bound broad reads and return paths for a batch", function()
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
		Verify.expect(compact.ok):toBe(true)
		Verify.expect(#compact.stdout <= 4096):toBe(true)
		Verify.expect(string.find(compact.stdout, "Open one path", 1, true) ~= nil):toBe(true)
		local full = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "VirtualList", "VirtualGrid", "--full" })
		Verify.expect(full.ok):toBe(true)
		local _, lists = string.gsub(full.stdout, "VirtualList.card %-", "")
		local _, grids = string.gsub(full.stdout, "VirtualGrid.card %-", "")
		Verify.expect(lists):toBe(1)
		Verify.expect(grids):toBe(1)
		Verify.expect(string.find(full.stdout, "```luau", 1, true) == nil):toBe(true)
		local card = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "VirtualGrid.card" })
		Verify.expect(card.ok):toBe(true)
		Verify.expect(string.find(card.stdout, "minColumnWidth", 1, true) ~= nil):toBe(true)
	end)
	harness:case("author setup and task recipes fit a short first read", function()
		local info = Run.capture({ Run.lute(), "run", "tools/facet", "info" })
		Verify.expect(info.ok):toBe(true)
		Verify.expect(#info.stdout < 3200):toBe(true)
		local recipes = Run.capture({ Run.lute(), "run", "tools/facet", "docs", "Tasks.collection-detail" })
		Verify.expect(recipes.ok):toBe(true)
		Verify.expect(#recipes.stdout <= 2048):toBe(true)
		Verify.expect(string.find(recipes.stdout, "Facet.Readable<Item>", 1, true) ~= nil):toBe(true)
	end)
	harness:case(
		"lint keeps all error locations and full details when it shortens cyclic type errors",
		function(context)
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
				[[--!strict
local Facet = require(game.ReplicatedStorage.Packages.Facet)
local app = Facet.app()
local UI = app.UI
type Entry = { id: string, title: string }
local entries: { Entry } = {}
local initial: { name: string, enabled: boolean }? = nil
local state = Facet.Compose.cell(initial)
local wrong: Facet.Readable<Entry> = state
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
]]
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
			Verify.expect(compact.ok):toBe(false)
			Verify.expect(full.ok):toBe(false)
			Verify.expect(string.find(compact.stdout, "function(use: Facet.Use)", 1, true) ~= nil):toBe(true)
			Verify.expect(string.find(compact.stdout, "[shortened]", 1, true) ~= nil):toBe(true)
			Verify.expect(#compact.stdout < #full.stdout):toBe(true)
			local report = Files.read("artifacts/facet-lint/report.txt")
			local _, reportLocations = string.gsub(report, ": error %[types%]", "")
			local _, fullLocations = string.gsub(full.stdout, ": error %[types%]", "")
			Verify.expect(reportLocations):toBe(fullLocations)
			Verify.expect(string.find(compact.stdout, "artifacts/facet-lint/report.txt", 1, true) ~= nil):toBe(true)
			Verify.expect(string.find(report, "(*CYCLE*)", 1, true) ~= nil):toBe(true)
		end
	)
	harness:case("the public surface checker detects removed, added and changed exports", function()
		local result = Run.capture({ Run.lute(), "run", "tools/engine/check_public_surface.luau", "--selftest" })
		Verify.expect(result.ok):toBe(true)
		Verify.expect(string.find(result.stdout, "SELFTEST PASS", 1, true) ~= nil):toBe(true)
	end)
	harness:case("module loader resolves an explicit Luau file before directory candidates", {
		id = "tools/commands::loader::explicit Luau file",
		run = function()
			local loader = Loader.new()
			local explicit = loader.require("src/ui/rich_text.luau")
			Verify.expect(loader.require("src/ui/rich_text")):toBe(explicit)
			Verify.expect(type(explicit)):toBe("table")
		end,
	})
	harness:case("module loader reports a missing explicit Luau file", {
		id = "tools/commands::loader::missing Luau file",
		run = function()
			local ok, failure = pcall(Loader.new().require, "tests/lib/missing-macos-loader-fixture.luau")
			Verify.expect(ok):toBe(false)
			Verify.expect(string.find(tostring(failure), "no module at ", 1, true) ~= nil):toBe(true)
		end,
	})
	for _, command in commands do
		local build = command.cases
		if build == nil then
			continue
		end
		harness:suite(command.name, function()
			for _, case in build() do
				harness:case(case.name, {
					id = ("tools/commands::%s::%s"):format(command.name, case.name),
					tags = case.tags,
					run = function()
						Verify.expect(case.run()):toBe(nil)
					end,
				})
			end
		end)
	end
end
