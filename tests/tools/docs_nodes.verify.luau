--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Index = require("../../tools/facet/lib/docs_index")
local DocsQuery = require("../../tools/facet/lib/docs_query")
local Cli = require("../../tools/facet/lib/cli")
local Files = require("../../tools/facet/lib/files")
local Props = require("../../tools/facet/lib/docs_props")
local Run = require("../../tools/facet/lib/run")

local function node(path: string, kind: string, body: string, children: { string }?): Index.Node
	return {
		path = path,
		file = "docs/reference/nodes/" .. path .. ".md",
		kind = kind,
		body = body,
		summary = path .. " options.",
		aliases = {},
		children = children or {},
	}
end

return function(harness: Verify.Harness)
	harness:case("control option near misses select the typed list without source output", function(t)
		for _, query in { "Stack", "Picker.style", "UI.Picker.props", "Button.missingOption" } do
			local result = Run.capture({ Run.lute(), "run", "tools/facet", "docs", query })
			t:expect(result.ok):toBe(true)
			t:expect(string.find(result.stdout, ".props", 1, true) ~= nil):toBe(true)
			t:expect((string.find(result.stdout, "export type", 1, true))):toBe(nil)
			t:expect(#result.stdout < 4096):toBe(true)
		end
	end)
	harness:case("typed option lookup follows public types in the repository and author kit", function(t)
		local lookup = Props.load(".")
		for _, control in
			{
				"VStack",
				"HStack",
				"Stack",
				"Picker",
				"Button",
				"Card",
				"Sheet",
				"VirtualList",
				"Table",
				"ColorPicker",
				"NavigationStack",
			}
		do
			local options = assert(lookup[control], control)
			t:expect(#options > 0):toBe(true)
			local output = Props.render(control, options)
			t:expect((string.find(output, "typeof(", 1, true))):toBe(nil)
			t:expect(#output < 4096):toBe(true)
		end
		local picker = Props.render("Picker", lookup.Picker)
		for _, field in
			{ 'style: ("automatic" | "menu"', "selected: Cell<V>", "options: Value<{ PickerOption<V> }>", "onChange:" }
		do
			t:expect(string.find(picker, field, 1, true) ~= nil):toBe(true)
		end
		local root = Files.temporaryDirectory("facet-props")
		t:defer(function()
			Files.remove(root)
		end)
		Files.write(
			Files.join(root, "Packages/Facet/ui/control_types.luau"),
			'local Props = require("./sample")\nexport type Controls = { Sample: Constructor<Props.Sample, Frame> }'
		)
		Files.write(
			Files.join(root, "Packages/Facet/ui/sample.luau"),
			"export type Sample = { required: string, optional: number?, Size: UDim2? }"
		)
		local sample = Props.render("Sample", assert(Props.load(root).Sample))
		t:expect(string.find(sample, "required: string = required", 1, true) ~= nil):toBe(true)
		t:expect(string.find(sample, "optional: number? = omitted", 1, true) ~= nil):toBe(true)
		t:expect((string.find(sample, "Size:", 1, true))):toBe(nil)
	end)
	harness:case("node files supply paths, kinds, sentences, aliases and ordered links without a manifest", function(t)
		local root = Files.temporaryDirectory("facet-docs")
		t:defer(function()
			Files.remove(root)
		end)
		local function write(name: string, body: string)
			Files.write(Files.join(root, "docs/reference/nodes", name .. ".md"), body)
		end
		write(
			"Map",
			"# Map\r\n\r\nStart here. Another sentence.\r\n\r\n[Tasks](Tasks.md) [Card](Button.card.md#call) [Tasks again](./Tasks.md)\r\n[Outside](../api.md) [External](https://example.com/X.md)\r\n```luau\r\n[Fake](Fake.md)\r\n```\r\n"
		)
		write("Tasks", "# Tasks\n\nChoose a task.\n")
		write("Tasks.shop", "# Shop\n\nBuy items.\n")
		write("Button.card", "# Button\n\nPress an action.\n\n<!-- aliases: push button | push -->\n")
		write("Text.card", "# Text\n\nRead a value.\n")
		write("Themes.index", "# Themes\n\nChoose a theme.\n")
		write("Themes.neutral.tokens", "# Tokens\n\nSet tokens.\n")
		write("Controls.1", "# Controls\n\nChoose a card.\n")
		write("Group.part", "# Group\n\n<!-- kind: index -->\n\nChoose a part.\n")
		write("Button.options", "### Options\n\nSet `UI.Button` options\nfor an action. Use the defaults.\n")
		local nodes = Index.load(root)
		t:expect(#nodes):toBe(10)
		local map = assert(Index.find(nodes, "Map"))
		t:expect(map.summary):toBe("Start here.")
		t:expect(table.concat(map.children, ",")):toBe("Tasks,Button.card,Tasks")
		for _, pair in
			{
				{ "Map", "map" },
				{ "Tasks", "index" },
				{ "Tasks.shop", "recipe" },
				{ "Button.card", "card" },
				{ "Themes.index", "index" },
				{ "Themes.neutral.tokens", "index" },
				{ "Controls.1", "index" },
				{ "Group.part", "index" },
				{ "Button.options", "detail" },
			}
		do
			t:expect(assert(Index.find(nodes, pair[1])).kind):toBe(pair[2])
		end
		local card = assert(Index.find(nodes, "push"))
		t:expect(card.path):toBe("Button.card")
		t:expect(table.concat(card.aliases, ",")):toBe("push button,push")
		t:expect(table.concat(assert(Index.find(nodes, "Text.card")).aliases, ",")):toBe("Text,UI.Text")
		t:expect((string.find(card.body, "<!--", 1, true))):toBe(nil)
		t:expect(assert(Index.find(nodes, "Button.options")).summary):toBe("Set `UI.Button` options for an action.")
	end)
	harness:case(
		"derived invalid nodes fail for titles, names, source bytes, missing links and reachability",
		function(t)
			local root = Files.temporaryDirectory("facet-docs-invalid")
			t:defer(function()
				Files.remove(root)
			end)
			local directory = Files.join(root, "docs/reference/nodes")
			Files.write(Files.join(directory, "Map.md"), "# Map\n\nStart here.\n\n[Missing](Missing.md)\n")
			Files.write(Files.join(directory, "Untitled.md"), "No title.\n")
			Files.write(Files.join(directory, "Bad name.md"), "# Bad name\n\nInvalid name.\n")
			Files.write(
				Files.join(directory, "Large.card.md"),
				"# Large\n\nAn action.\n\n<!-- aliases: " .. string.rep("x", 1024) .. " -->\n"
			)
			local findings = table.concat(Index.validate(Index.load(root)), "\n")
			for _, expected in
				{
					"Untitled: missing title",
					"Bad name: unknown kind",
					"Large.card:",
					"exceeds 1024",
					"missing child Missing",
					"Untitled: unreachable from Map",
				}
			do
				t:expect(string.find(findings, expected, 1, true) ~= nil):toBe(true)
			end
		end
	)
	harness:case("shared aliases select the shortest path independently of traversal order", function(t)
		local first = node("DateTimePicker.Proposals-and-commits", "detail", "# Date\n\nDate proposals.\n")
		local second = node("Proposals-and-commits", "detail", "# Colour\n\nColour proposals.\n")
		first.aliases = { "Proposals and commits" }
		second.aliases = { "Proposals and commits" }
		t:expect(assert(Index.find({ first, second }, "Proposals and commits")).path):toBe(second.path)
		t:expect(assert(Index.find({ second, first }, "Proposals and commits")).path):toBe(second.path)
	end)
	harness:case("oversize, orphan and missing child nodes fail the repository check", function(t)
		local nodes = {
			node("Map", "map", "[Card](Card.md)", { "Card", "Missing" }),
			node("Card", "card", string.rep("x", 1025)),
			node("Orphan", "detail", "Unlinked."),
		}
		local findings = table.concat(Index.validate(nodes), "\n")
		t:expect(string.find(findings, "exceeds 1024", 1, true) ~= nil):toBe(true)
		t:expect(string.find(findings, "missing child Missing", 1, true) ~= nil):toBe(true)
		t:expect(string.find(findings, "Orphan: unreachable", 1, true) ~= nil):toBe(true)
	end)
	harness:case("full and batched calls cannot print large contracts", function(t)
		local nodes = {
			node("Map", "map", "Map."),
			node("Long", "detail", string.rep("SECRET", 800), { "Detail" }),
			node("Detail", "detail", "Exact detail."),
		}
		local full = DocsQuery.response(nodes, Cli.parse({ "docs", "Long", "--full" }))
		t:expect(string.find(full, "SECRET", 1, true) == nil):toBe(true)
		t:expect(string.find(full, "Detail", 1, true) ~= nil):toBe(true)
		local batch = DocsQuery.response(nodes, Cli.parse({ "docs", "Long", "Detail", "--full" }))
		t:expect(string.find(batch, "Exact detail.", 1, true) == nil):toBe(true)
		t:expect(#batch <= 4096):toBe(true)
	end)
	harness:case("every repository query and search stays within the response budget", function(t)
		local nodes = Index.load(".")
		t:expect(#Index.validate(nodes)):toBe(0)
		for _, item in nodes do
			if item.kind == "card" then
				local control = string.sub(item.path, 1, -6)
				t:expect(item.aliases[1]):toBe(control)
				t:expect(item.aliases[2]):toBe("UI." .. control)
			end
			local output = DocsQuery.response(nodes, Cli.parse({ "docs", item.path, "--full" }))
			t:expect(#output + 1 <= 4096):toBe(true)
		end
		t:expect(#DocsQuery.response(nodes, Cli.parse({ "docs" })) <= 2048):toBe(true)
		local search = DocsQuery.response(nodes, Cli.parse({ "docs", "--search", "detent" }, { "search" }))
		t:expect(string.find(search, "Sheet.detents", 1, true) ~= nil):toBe(true)
		t:expect(string.find(search, "Sheet.detents - ", 1, true) ~= nil):toBe(true)
	end)
	harness:case("missed names resolve to useful nodes and ambiguous names stay short", function(t)
		local nodes = Index.load(".")
		for _, pair in
			{
				{ "ProgressBar.card", "ProgressView.card" },
				{ "Progress.card", "ProgressView.card" },
				{ "Stack.layout", "Layout-options" },
				{ "VStack.layout", "Layout-options" },
				{ "Text.typography", "Text.textRole" },
				{ "app", "Mounting.Facet.app" },
				{ "Compose.show", "State" },
				{ "Buton.card", "Button.card" },
			}
		do
			local result = DocsQuery.response(nodes, Cli.parse({ "docs", pair[1] }))
			t:expect(string.find(result, `Resolved '{pair[1]}' to {pair[2]}.`, 1, true) == 1):toBe(true)
			t:expect(#result + 1 <= Index.responseBudget):toBe(true)
		end
		local ambiguous = { node("Alpha.one", "detail", "One."), node("Alpha.two", "detail", "Two.") }
		local result = DocsQuery.response(ambiguous, Cli.parse({ "docs", "Alpha" }))
		t:expect(string.find(result, "No documentation node", 1, true) == 1):toBe(true)
		t:expect(string.find(result, "Alpha.one", 1, true) ~= nil):toBe(true)
		t:expect(Index.nearest(ambiguous, "Alpha.owe")):toBe(nil)
	end)
	harness:case("the map and HUD route each screen task to its recipe", function(t)
		local nodes = Index.load(".")
		t:expect(string.find(assert(Index.find(nodes, "Map")).body, "every task recipe", 1, true) ~= nil):toBe(true)
		local hud = assert(Index.find(nodes, "Tasks.hud"))
		t:expect(table.find(hud.children, "Tasks.shop") ~= nil):toBe(true)
		t:expect(table.find(hud.children, "Tasks.sheet") ~= nil):toBe(true)
		local shop = assert(Index.find(nodes, "Tasks.shop"))
		for _, name in { "UI.Sheet", "UI.VirtualList", "owned", "applyResult", "feedback", "onActivate" } do
			t:expect(string.find(shop.body, name, 1, true) ~= nil):toBe(true)
		end
	end)
end
