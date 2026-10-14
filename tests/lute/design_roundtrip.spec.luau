--!strict
local Verify = require("../../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local syntax = require("@std/syntax")
	local printer = require("@std/syntax/printer")
	local Document = require("../../tools/facet/design/document")
	local Operations = require("../../tools/facet/design/operations")
	local SourceMap = require("../../tools/facet/design/source_map")
	local Cst = require("../../tools/facet/design/cst")
	local Fixtures = require("./design_fixtures")

	local function corpus(): { string }
		local files = Fixtures.walk("examples")
		for _, path in Fixtures.walk("src") do
			table.insert(files, path)
		end
		return files
	end

	verifyHarness:suite("Design source round trip", function()
		verifyHarness:case("prints every example and source module byte for byte from its syntax tree", {
			id = "lute/design_roundtrip::Design source round trip::prints every example and source module byte for byte from its syntax tree",
			run = function(context)
				local files = corpus()
				local failures: { string } = {}
				local bytes = 0
				for _, path in files do
					local source = Fixtures.read(path)
					bytes += #source
					local map, problem = SourceMap.parse(source)
					if map == nil then
						table.insert(failures, path .. ": " .. tostring(problem))
					elseif map.printed ~= source then
						table.insert(failures, path .. ": the printed source differs")
					end
				end
				context:attach(
					"roundtrip.txt",
					"text/plain",
					("%d files, %d bytes, %d not byte-identical\n%s"):format(
						#files,
						bytes,
						#failures,
						table.concat(failures, "\n")
					)
				)
				Verify.expect(#files > 300):toBe(true)
				Verify.expect(failures):toEqual({})
			end,
		})

		verifyHarness:case("limits stock printer differences to parenthesized type arguments", {
			id = "lute/design_roundtrip::Design source round trip::limits stock printer differences to parenthesized type arguments",
			run = function(context)
				local differing: { string } = {}
				local unexplained: { string } = {}
				for _, path in corpus() do
					local source = Fixtures.read(path)
					local printed = printer.printFile(syntax.parse(source))
					if printed ~= source then
						table.insert(differing, path)
						local index = 1
						while string.byte(source, index) == string.byte(printed, index) do
							index += 1
						end
						local window = string.sub(source, math.max(1, index - 2), index + 1)
						if string.find(window, "<(", 1, true) == nil then
							table.insert(unexplained, path)
						end
					end
				end
				context:attach("stock-printer.txt", "text/plain", table.concat(differing, "\n") .. "\n")
				Verify.expect(unexplained):toEqual({})
			end,
		})

		verifyHarness:case("parses each Facet Home design as a tree of controls with literal values classified", {
			id = "lute/design_roundtrip::Design source round trip::parses each Facet Home design as a tree of controls with literal values classified",
			run = function(context)
				local schema = Fixtures.schema()
				local designs = 0
				local opaque: { string } = {}
				for _, path in Fixtures.walk("examples/facet_home/designs") do
					if string.match(path, "/%u%w+%.luau$") and not string.find(path, "%.preview%.luau$") then
						designs += 1
						local doc = Document.parse(Fixtures.read(path), schema)
						Verify.expect(doc.error):toBeNil()
						Verify.expect(doc.problems):toEqual({})
						Verify.expect(doc.root ~= nil):toBe(true)
						for _, node in doc.order do
							Verify.expect(node.type):toBe("control")
							for _, prop in node.props do
								if prop.value.kind == "code" then
									local expr = Cst.parseExpr(prop.value.text :: string)
									Verify.expect(expr.tag == "string" or expr.tag == "number" or expr.tag == "boolean")
										:toBe(false)
									table.insert(opaque, node.id .. "." .. prop.name)
								end
							end
						end
					end
				end
				context:attach("opaque-values.txt", "text/plain", table.concat(opaque, "\n") .. "\n")
				Verify.expect(designs):toBe(6)
			end,
		})

		verifyHarness:case("leaves every design byte unchanged when each property gets its current value", {
			id = "lute/design_roundtrip::Design source round trip::leaves every design byte unchanged when each property gets its current value",
			run = function()
				local schema = Fixtures.schema()
				local checked = 0
				for _, path in Fixtures.walk("examples/facet_home/designs") do
					if string.find(path, "%.preview%.luau$") then
						continue
					end
					local source = Fixtures.read(path)
					local doc = Document.parse(source, schema)
					local ops: { unknown } = {}
					for _, node in doc.order do
						if node.label then
							table.insert(ops, { op = "rename", node = node.id, label = node.label })
						end
						for _, prop in node.props do
							local value = prop.value
							if
								value.kind == "string"
								or value.kind == "token"
								or value.kind == "number"
								or value.kind == "boolean"
							then
								table.insert(ops, {
									op = "set_prop",
									node = node.id,
									prop = prop.name,
									value = { kind = value.kind, value = value.value, cast = value.cast == true },
								})
								checked += 1
							end
						end
					end
					local result, problem = Operations.apply(doc, schema, ops)
					Verify.expect(problem):toBeNil()
					Verify.expect((result :: Operations.BatchResult).doc.source == source):toBe(true)
					Verify.expect(#(result :: Operations.BatchResult).inverse):toBe(0)
				end
				Verify.expect(checked > 50):toBe(true)
			end,
		})

		verifyHarness:case("keeps CRLF files, comments and long strings intact after an unrelated edit", {
			id = "lute/design_roundtrip::Design source round trip::keeps CRLF files, comments and long strings intact after an unrelated edit",
			run = function()
				local schema = Fixtures.schema()
				local crlf = Document.parse(Fixtures.CRLF, schema)
				local edited = Operations.apply(crlf, schema, {
					{
						op = "insert",
						parent = "Screen",
						node = { kind = "Text", label = "Body", props = { text = "Body" } },
					},
				})
				local text = (edited :: Operations.BatchResult).doc.source
				Verify.expect((string.find((string.gsub(text, "\r\n", "")), "\n", 1, true))):toBeNil()
				Verify.expect(
					string.find(text, 'UI.Text "Body" {\r\n\t\t\ttext = "Body",\r\n\t\t},\r\n', 1, true) ~= nil
				)
					:toBe(true)
				local rich = Document.parse(Fixtures.RICH, schema)
				local changed = Operations.apply(
					rich,
					schema,
					{ { op = "set_prop", node = "Close", prop = "label", value = "Done" } }
				)
				local after = (changed :: Operations.BatchResult).doc.source
				Verify.expect(string.find(after, "-- The panel lists the inventory.", 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(after, 'gap = "s", -- tight rows', 1, true) ~= nil):toBe(true)
				Verify.expect(string.find(after, "[[\nFirst line\n\tSecond line]]", 1, true) ~= nil):toBe(true)
				Verify.expect(#after):toBe(#Fixtures.RICH - 1)
			end,
		})
	end)
end
