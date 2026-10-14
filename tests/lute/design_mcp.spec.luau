--!strict
local Verify = require("../../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local fs = require("@std/fs")
	local Mcp = require("../../tools/facet/design/mcp")
	local Registry = require("../../tools/facet/design/registry")
	local Wire = require("../../tools/facet/design/wire")
	local Fixtures = require("./design_fixtures")

	local schema = Fixtures.schema()

	local function session(root: string?): Mcp.Session
		return Mcp.session({ root = root, schema = schema, version = "test" })
	end

	local function exchange(state: Mcp.Session, message: { [string]: unknown }): { [string]: unknown }?
		local reply = Mcp.handle(state, Wire.encode(message))
		if reply == nil then
			return nil
		end
		Verify.expect((string.find(reply, "\n", 1, true))):toBeNil()
		local ok, decoded = Wire.decode(reply)
		Verify.expect(ok):toBe(true)
		return decoded :: { [string]: unknown }
	end

	local function initialize(state: Mcp.Session)
		exchange(state, {
			jsonrpc = "2.0",
			id = 1,
			method = "initialize",
			params = {
				protocolVersion = "2025-06-18",
				capabilities = {},
				clientInfo = { name = "Claude Code", version = "2" },
			},
		})
		exchange(state, { jsonrpc = "2.0", method = "notifications/initialized" })
	end

	local function result(reply: { [string]: unknown }?): { [string]: unknown }
		return (assert(reply, "expected a reply") :: { [string]: unknown }).result :: { [string]: unknown }
	end

	verifyHarness:suite("Design MCP", function()
		verifyHarness:case("negotiates the protocol and names the client as the author", {
			id = "lute/design_mcp::Design MCP::negotiates the protocol and names the client as the author",
			run = function()
				local state = session()
				local reply = exchange(state, {
					jsonrpc = "2.0",
					id = 1,
					method = "initialize",
					params = {
						protocolVersion = "2025-03-26",
						capabilities = {},
						clientInfo = { name = "Claude Code", version = "2" },
					},
				})
				local body = result(reply)
				Verify.expect((reply :: { [string]: unknown }).id):toBe(1)
				Verify.expect(body.protocolVersion):toBe("2025-03-26")
				Verify.expect(Wire.field(Wire.field(body, "capabilities"), "tools") ~= nil):toBe(true)
				Verify.expect(Wire.field(body.serverInfo, "name")):toBe("facet-design")
				Verify.expect(state.context.author):toBe("agent:claude-code")
				local unknown = session()
				local fallback = result(exchange(unknown, {
					jsonrpc = "2.0",
					id = "a",
					method = "initialize",
					params = { protocolVersion = "1999-01-01" },
				}))
				Verify.expect(fallback.protocolVersion):toBe(Mcp.PROTOCOLS[1])
			end,
		})

		verifyHarness:case("sends no reply to notifications and answers ping", {
			id = "lute/design_mcp::Design MCP::sends no reply to notifications and answers ping",
			run = function()
				local state = session()
				Verify.expect(exchange(state, { jsonrpc = "2.0", method = "notifications/initialized" })):toBeNil()
				Verify.expect(
					exchange(state, { jsonrpc = "2.0", method = "notifications/cancelled", params = { requestId = 3 } })
				)
					:toBeNil()
				Verify.expect(state.initialized):toBe(true)
				local pong = exchange(state, { jsonrpc = "2.0", id = 7, method = "ping" })
				Verify.expect(Mcp.handle(state, Wire.encode({ jsonrpc = "2.0", id = 7, method = "ping" })))
					:toBe('{"id":7,"jsonrpc":"2.0","result":{}}')
				Verify.expect((pong :: { [string]: unknown }).id):toBe(7)
			end,
		})

		verifyHarness:case("lists every public registry operation with a JSON schema", {
			id = "lute/design_mcp::Design MCP::lists every public registry operation with a JSON schema",
			run = function()
				local state = session()
				initialize(state)
				local tools =
					result(exchange(state, { jsonrpc = "2.0", id = 2, method = "tools/list" })).tools :: { { [string]: unknown } }
				local names: { string } = {}
				for _, tool in tools do
					table.insert(names, tool.name :: string)
					local schemaObject = tool.inputSchema :: { [string]: unknown }
					Verify.expect(schemaObject.type):toBe("object")
					Verify.expect(type(tool.description)):toBe("string")
				end
				Verify.expect(#tools):toBe(#Registry.list())
				for _, expected in
					{
						"query_tree",
						"get_node",
						"set_prop",
						"unset_prop",
						"insert",
						"remove",
						"move",
						"wrap",
						"unwrap",
						"rename",
						"bind",
						"unbind",
						"set_token",
						"duplicate",
						"apply",
						"undo",
						"redo",
						"comment_add",
						"comment_reply",
						"comment_resolve",
						"comment_list",
						"schema_controls",
						"schema_control",
						"docs",
					}
				do
					Verify.expect(names):toContain(expected)
				end
				Verify.expect(names).never:toContain("restore_entries")
				local query = tools[table.find(names, "query_tree") :: number]
				Verify.expect(Wire.field(query.annotations, "readOnlyHint")):toBe(true)
				local required = Wire.field(query.inputSchema, "required") :: { string }
				Verify.expect(required):toContain("file")
			end,
		})

		verifyHarness:case("calls tools and reports tool failures as error results", {
			id = "lute/design_mcp::Design MCP::calls tools and reports tool failures as error results",
			run = function(test)
				local path = Fixtures.file("mcp", Fixtures.SMALL)
				local directory = string.match(path, "^(.*)/[^/]+$") :: string
				test:defer(function()
					Fixtures.remove(directory)
				end)
				local state = session(directory)
				initialize(state)
				local tree = result(exchange(state, {
					jsonrpc = "2.0",
					id = 3,
					method = "tools/call",
					params = { name = "query_tree", arguments = { file = "View.luau", depth = 1 } },
				}))
				Verify.expect(tree.isError):toBe(false)
				local structured = tree.structuredContent :: { [string]: unknown }
				Verify.expect(Wire.field(structured.root, "id")):toBe("Screen")
				local content = (tree.content :: { { [string]: unknown } })[1]
				Verify.expect(content.type):toBe("text")
				local hash = structured.hash :: string
				local changed = result(exchange(state, {
					jsonrpc = "2.0",
					id = 4,
					method = "tools/call",
					params = {
						name = "set_prop",
						arguments = {
							file = "View.luau",
							base = hash,
							node = "Heading",
							prop = "text",
							value = "Agent",
						},
					},
				}))
				Verify.expect(changed.isError):toBe(false)
				Verify.expect(fs.readFileToString(path)):toContain('text = "Agent"')
				local stale = result(exchange(state, {
					jsonrpc = "2.0",
					id = 5,
					method = "tools/call",
					params = {
						name = "set_prop",
						arguments = { file = "View.luau", base = hash, node = "Heading", prop = "text", value = "Late" },
					},
				}))
				Verify.expect(stale.isError):toBe(true)
				Verify.expect(Wire.field(Wire.field(stale.structuredContent, "error"), "code")):toBe("stale")
				local undone = result(exchange(state, {
					jsonrpc = "2.0",
					id = 6,
					method = "tools/call",
					params = { name = "undo", arguments = { file = "View.luau" } },
				}))
				Verify.expect(undone.isError):toBe(false)
				Verify.expect(fs.readFileToString(path)):toBe(Fixtures.SMALL)
				local invalid = result(exchange(state, {
					jsonrpc = "2.0",
					id = 7,
					method = "tools/call",
					params = { name = "remove", arguments = { file = "View.luau" } },
				}))
				Verify.expect(invalid.isError):toBe(true)
				Verify.expect(Wire.field(Wire.field(invalid.structuredContent, "error"), "message"))
					:toContain("node is required")
			end,
		})

		verifyHarness:case("returns JSON-RPC errors for bad frames, unknown methods and unknown tools", {
			id = "lute/design_mcp::Design MCP::returns JSON-RPC errors for bad frames, unknown methods and unknown tools",
			run = function()
				local state = session()
				local parse = Wire.decode(Mcp.handle(state, "{not json") :: string)
				local _, parsed = Wire.decode(Mcp.handle(state, "{not json") :: string)
				Verify.expect(parse):toBe(true)
				Verify.expect(Wire.field(Wire.field(parsed, "error"), "code")):toBe(Mcp.PARSE_ERROR)
				Verify.expect(string.find(Mcp.handle(state, "{not json") :: string, '"id":null', 1, true) ~= nil)
					:toBe(true)
				local invalid = exchange(state, { id = 1, method = "ping" }) :: { [string]: unknown }
				Verify.expect(Wire.field(invalid.error, "code")):toBe(Mcp.INVALID_REQUEST)
				local missing =
					exchange(state, { jsonrpc = "2.0", id = 2, method = "resources/read" }) :: { [string]: unknown }
				Verify.expect(Wire.field(missing.error, "code")):toBe(Mcp.METHOD_NOT_FOUND)
				local tool = exchange(state, {
					jsonrpc = "2.0",
					id = 3,
					method = "tools/call",
					params = { name = "restore_expr", arguments = {} },
				}) :: { [string]: unknown }
				Verify.expect(Wire.field(tool.error, "code")):toBe(Mcp.INVALID_PARAMS)
				Verify.expect(Mcp.handle(state, "   ")):toBeNil()
			end,
		})

		verifyHarness:case("frames newline-delimited messages across arbitrary read chunks", {
			id = "lute/design_mcp::Design MCP::frames newline-delimited messages across arbitrary read chunks",
			run = function()
				local state = session()
				local stream = table.concat({
					Wire.encode({
						jsonrpc = "2.0",
						id = 1,
						method = "initialize",
						params = { clientInfo = { name = "probe" } },
					}),
					Wire.encode({ jsonrpc = "2.0", method = "notifications/initialized" }),
					Wire.encode({ jsonrpc = "2.0", id = 2, method = "ping" }),
					Wire.encode({
						{ jsonrpc = "2.0", id = 3, method = "ping" } :: unknown,
						{ jsonrpc = "2.0", method = "notifications/initialized" } :: unknown,
					}),
				}, "\r\n") .. "\n" .. Wire.encode({ jsonrpc = "2.0", id = 4, method = "ping" })
				local chunks: { string } = {}
				local index = 1
				local size = 1
				while index <= #stream do
					table.insert(chunks, string.sub(stream, index, index + size - 1))
					index += size
					size = (size % 17) + 3
				end
				local written: { string } = {}
				local position = 0
				Mcp.serve(state, function(): string?
					position += 1
					return chunks[position]
				end, function(text: string)
					table.insert(written, text)
				end)
				Verify.expect(#written):toBe(4)
				for _, text in written do
					Verify.expect(string.sub(text, -1)):toBe("\n")
				end
				local _, batch = Wire.decode(written[3])
				Verify.expect(#Wire.list(batch)):toBe(1)
				local _, last = Wire.decode(written[4])
				Verify.expect(Wire.field(last, "id")):toBe(4)
				Verify.expect(state.context.author):toBe("agent:probe")
			end,
		})
	end)
end
