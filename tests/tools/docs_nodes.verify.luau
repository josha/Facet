--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Index = require("../../tools/facet/lib/docs_index")
local DocsQuery = require("../../tools/facet/lib/docs_query")
local Cli = require("../../tools/facet/lib/cli")
local Files = require("../../tools/facet/lib/files")

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
				t:expect(table.concat(item.aliases, ",")):toBe(control .. ",UI." .. control)
			end
			local output = DocsQuery.response(nodes, Cli.parse({ "docs", item.path, "--full" }))
			t:expect(#output + 1 <= 4096):toBe(true)
		end
		t:expect(#DocsQuery.response(nodes, Cli.parse({ "docs" })) <= 2048):toBe(true)
		local search = DocsQuery.response(nodes, Cli.parse({ "docs", "--search", "detent" }, { "search" }))
		t:expect(string.find(search, "Sheet.detents", 1, true) ~= nil):toBe(true)
		t:expect(string.find(search, "Sheet.detents - ", 1, true) ~= nil):toBe(true)
	end)
end
