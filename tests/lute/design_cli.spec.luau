--!strict
local Verify = require("../../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local fs = require("@std/fs")
	local process = require("@std/process")
	local Registry = require("../../tools/facet/design/registry")
	local Wire = require("../../tools/facet/design/wire")
	local Fixtures = require("./design_fixtures")

	local function facet(arguments: { string }): process.ProcessResult
		local command = { "lute", "run", Fixtures.root() .. "/tools/facet" }
		for _, argument in arguments do
			table.insert(command, argument)
		end
		return process.run(command, { cwd = Fixtures.root() })
	end

	local function decode(result: process.ProcessResult): { [string]: unknown }
		local ok, decoded = Wire.decode(result.stdout)
		if not ok then
			error("the command printed no JSON: " .. result.stdout .. result.stderr, 2)
		end
		return decoded :: { [string]: unknown }
	end

	verifyHarness:suite("Design command line", function()
		verifyHarness:case("prints a tree, applies a batch, undoes it and shows the history", {
			id = "lute/design_cli::Design command line::prints a tree, applies a batch, undoes it and shows the history",
			run = function(test)
				local path = Fixtures.file("cli", Fixtures.SMALL)
				local directory = string.match(path, "^(.*)/[^/]+$") :: string
				test:defer(function()
					Fixtures.remove(directory)
				end)
				local tree = facet({ "design", "tree", path })
				Verify.expect(tree.ok):toBe(true)
				Verify.expect(tree.stdout):toContain("Screen/Heading  Text")
				local json = decode(facet({ "design", "tree", path, "--json" }))
				local hash = json.hash :: string
				local opsPath = directory .. "/ops.json"
				fs.writeStringToFile(
					opsPath,
					Wire.encode({
						base = hash,
						ops = { { op = "set_prop", node = "Heading", prop = "text", value = "From CLI" } },
					})
				)
				local applied = facet({ "design", "apply", path, opsPath, "--author=human:cli" })
				Verify.expect(applied.ok):toBeTrueWith(applied.stdout .. applied.stderr)
				Verify.expect(fs.readFileToString(path)):toContain('text = "From CLI"')
				local stale = facet({ "design", "apply", path, opsPath, "--author=human:cli" })
				Verify.expect(stale.ok):toBe(false)
				Verify.expect(stale.stdout):toContain("facet: stale:")
				local foreign = facet({ "design", "undo", path, "--author=agent:other" })
				Verify.expect(foreign.ok):toBe(false)
				local undone = facet({ "design", "undo", path, "--author=human:cli" })
				Verify.expect(undone.ok):toBeTrueWith(undone.stdout)
				Verify.expect(fs.readFileToString(path)):toBe(Fixtures.SMALL)
				local history = facet({ "design", "history", path })
				Verify.expect(history.stdout):toContain("human:cli")
				Verify.expect(history.stdout):toContain("(undone)")
			end,
		})

		verifyHarness:case("lists, describes and calls registry tools", {
			id = "lute/design_cli::Design command line::lists, describes and calls registry tools",
			run = function(test)
				local path = Fixtures.file("tool", Fixtures.SMALL)
				local directory = string.match(path, "^(.*)/[^/]+$") :: string
				test:defer(function()
					Fixtures.remove(directory)
				end)
				local listed = decode(facet({ "tool", "list", "--json" }))
				Verify.expect(#Wire.list(listed.tools)):toBe(#Registry.list())
				local described = decode(facet({ "tool", "describe", "move" }))
				Verify.expect(described.mutation):toBe("document")
				Verify.expect(described.capability):toBe("edit")
				local input =
					Wire.encode({ file = path, parent = "Screen", node = { kind = "Divider", label = "Rule" } })
				local called = decode(facet({ "tool", "call", "insert", input, "--author=agent:cli" }))
				Verify.expect(called.ok):toBe(true)
				Verify.expect(fs.readFileToString(path)):toContain('UI.Divider "Rule" {}')
				local refused = facet({ "tool", "call", "restore_expr", "{}" })
				Verify.expect(refused.ok):toBe(false)
			end,
		})

		verifyHarness:case("prints the control schema as text and JSON", {
			id = "lute/design_cli::Design command line::prints the control schema as text and JSON",
			run = function()
				local text = facet({ "schema", "--control=Text" })
				Verify.expect(text.stdout):toContain("text: Value<string>")
				local json = decode(facet({ "schema", "--json" }))
				Verify.expect(#Wire.list(json.controls) > 60):toBe(true)
				local help = facet({ "help" })
				for _, name in { "design", "tool", "mcp", "schema" } do
					Verify.expect(help.stdout):toContain("  " .. name)
				end
			end,
		})

		verifyHarness:case("returns sections of the design guide through the docs tool", {
			id = "lute/design_cli::Design command line::returns sections of the design guide through the docs tool",
			run = function()
				local context: Registry.Context = { author = "agent:test", root = Fixtures.root() }
				local all = Registry.call(context, "docs", {}) :: { [string]: unknown }
				Verify.expect(all.sections :: { string }):toContain("Editable subset")
				local section = Registry.call(context, "docs", { topic = "Node ids" }) :: { [string]: unknown }
				Verify.expect(section.text):toContain("Screen/Panel/Title")
				local _, missing = Registry.call(context, "docs", { topic = "Nothing here" })
				Verify.expect((missing :: Registry.Failure).code):toBe("not_found")
			end,
		})
	end)
end
