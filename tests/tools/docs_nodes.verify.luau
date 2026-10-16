--!strict
local Verify = require("../../tools/vendor/verify/src/core")
local Index = require("../../tools/facet/lib/docs_index")
local DocsQuery = require("../../tools/facet/lib/docs_query")
local Cli = require("../../tools/facet/lib/cli")

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
			local output = DocsQuery.response(nodes, Cli.parse({ "docs", item.path, "--full" }))
			t:expect(#output + 1 <= 4096):toBe(true)
		end
		t:expect(#DocsQuery.response(nodes, Cli.parse({ "docs" })) <= 2048):toBe(true)
		local search = DocsQuery.response(nodes, Cli.parse({ "docs", "--search", "detent" }, { "search" }))
		t:expect(string.find(search, "Sheet.detents", 1, true) ~= nil):toBe(true)
		t:expect(string.find(search, "Sheet.detents - ", 1, true) ~= nil):toBe(true)
	end)
end
