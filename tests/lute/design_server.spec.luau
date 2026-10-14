--!strict
local Verify = require("../../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local fs = require("@std/fs")
	local net = require("@lute/net")
	local task = require("@std/task")
	local Server = require("../../tools/facet/design/server")
	local Wire = require("../../tools/facet/design/wire")
	local Workspace = require("../../tools/facet/design/workspace")
	local Fixtures = require("./design_fixtures")

	local schema = Fixtures.schema()

	type Message = { [string]: unknown }
	type Inboxes = { [string]: { Message } }

	local function hub(label: string): (Server.Hub, Inboxes, string, string)
		local path = Fixtures.file(label, Fixtures.SMALL)
		local directory = string.match(path, "^(.*)/[^/]+$") :: string
		local inboxes: Inboxes = {}
		local state = Server.hub({
			root = directory,
			schema = schema,
			send = function(clientId: string, text: string)
				local ok, decoded = Wire.decode(text)
				assert(ok, "the server sent invalid JSON")
				inboxes[clientId] = inboxes[clientId] or {}
				table.insert(inboxes[clientId], decoded :: Message)
			end,
		})
		return state, inboxes, path, directory
	end

	local function join(state: Server.Hub, clientId: string, name: string, kind: string)
		Server.connect(state, clientId)
		Server.receive(state, clientId, Wire.encode({ type = "hello", client = { name = name, kind = kind } }))
	end

	local NONE: { Message } = {}

	local function last(inboxes: Inboxes, clientId: string, kind: string): Message?
		local inbox = inboxes[clientId] or NONE
		for index = #inbox, 1, -1 do
			if inbox[index].type == kind then
				return inbox[index]
			end
		end
		return nil
	end

	local function count(inboxes: Inboxes, clientId: string, kind: string): number
		local total = 0
		local inbox = inboxes[clientId] or NONE
		for _, message in inbox do
			if message.type == kind then
				total += 1
			end
		end
		return total
	end

	verifyHarness:suite("Design server", function()
		verifyHarness:case("greets clients and sends a snapshot with source and tree", {
			id = "lute/design_server::Design server::greets clients and sends a snapshot with source and tree",
			run = function(test)
				local state, inboxes, _, directory = hub("greet")
				test:defer(function()
					Fixtures.remove(directory)
				end)
				join(state, "c1", "studio", "plugin")
				local welcome = last(inboxes, "c1", "welcome") :: Message
				Verify.expect(Wire.field(welcome.client, "author")):toBe("plugin:studio")
				Verify.expect(#Wire.list(welcome.files)):toBe(1)
				Server.receive(state, "c1", Wire.encode({ type = "subscribe", file = "View.luau" }))
				local snapshot = last(inboxes, "c1", "snapshot") :: Message
				Verify.expect(snapshot.source):toBe(Fixtures.SMALL)
				Verify.expect(snapshot.hash):toBe(Workspace.hash(Fixtures.SMALL))
				Verify.expect(Wire.field(Wire.field(snapshot.tree, "root"), "id")):toBe("Screen")
			end,
		})

		verifyHarness:case("applies a batch once and broadcasts the update to every subscriber", {
			id = "lute/design_server::Design server::applies a batch once and broadcasts the update to every subscriber",
			run = function(test)
				local state, inboxes, path, directory = hub("broadcast")
				test:defer(function()
					Fixtures.remove(directory)
				end)
				join(state, "plugin", "studio", "plugin")
				join(state, "agent", "claude", "agent")
				for _, clientId in { "plugin", "agent" } do
					Server.receive(state, clientId, Wire.encode({ type = "subscribe", file = "View.luau" }))
				end
				local base = Workspace.hash(Fixtures.SMALL)
				Server.receive(
					state,
					"agent",
					Wire.encode({
						type = "apply",
						request = "r1",
						file = "View.luau",
						base = base,
						ops = { { op = "set_prop", node = "Heading", prop = "text", value = "From agent" } },
					})
				)
				local applied = last(inboxes, "agent", "applied") :: Message
				Verify.expect(applied.request):toBe("r1")
				for _, clientId in { "plugin", "agent" } do
					local update = last(inboxes, clientId, "update") :: Message
					Verify.expect(update.author):toBe("agent:claude")
					Verify.expect(update.origin):toBe("agent")
					Verify.expect(update.previous):toBe(base)
					Verify.expect(update.source):toContain('text = "From agent"')
				end
				Verify.expect(fs.readFileToString(path)):toContain('text = "From agent"')
				Server.poll(state)
				Verify.expect(count(inboxes, "plugin", "update")):toBe(1)
			end,
		})

		verifyHarness:case("rejects a stale batch and a batch without a base", {
			id = "lute/design_server::Design server::rejects a stale batch and a batch without a base",
			run = function(test)
				local state, inboxes, path, directory = hub("stale")
				test:defer(function()
					Fixtures.remove(directory)
				end)
				join(state, "a", "alice", "human")
				join(state, "b", "bob", "human")
				local base = Workspace.hash(Fixtures.SMALL)
				Server.receive(
					state,
					"a",
					Wire.encode({
						type = "apply",
						file = "View.luau",
						base = base,
						ops = { { op = "rename", node = "Go", label = "Start" } },
					})
				)
				Server.receive(
					state,
					"b",
					Wire.encode({
						type = "apply",
						request = 9,
						file = "View.luau",
						base = base,
						ops = { { op = "rename", node = "Go", label = "Begin" } },
					})
				)
				local rejected = last(inboxes, "b", "rejected") :: Message
				Verify.expect(rejected.request):toBe(9)
				Verify.expect(Wire.field(rejected.error, "code")):toBe("stale")
				Verify.expect(rejected.hash).never:toBe(base)
				Server.receive(
					state,
					"b",
					Wire.encode({ type = "apply", file = "View.luau", ops = { { op = "remove", node = "Start" } } })
				)
				local missing = last(inboxes, "b", "rejected") :: Message
				Verify.expect(Wire.field(missing.error, "message")):toContain("apply needs base")
				Verify.expect(fs.readFileToString(path)):toContain('UI.Button "Start"')
			end,
		})

		verifyHarness:case("relays presence to other subscribers and announces departures", {
			id = "lute/design_server::Design server::relays presence to other subscribers and announces departures",
			run = function(test)
				local state, inboxes, _, directory = hub("presence")
				test:defer(function()
					Fixtures.remove(directory)
				end)
				join(state, "a", "alice", "human")
				join(state, "b", "claude", "agent")
				Server.receive(state, "a", Wire.encode({ type = "subscribe", file = "View.luau" }))
				Server.receive(state, "b", Wire.encode({ type = "subscribe", file = "View.luau" }))
				Server.receive(
					state,
					"b",
					Wire.encode({ type = "presence", file = "View.luau", node = "Screen/Heading" })
				)
				local seen = last(inboxes, "a", "presence") :: Message
				Verify.expect(seen.node):toBe("Screen/Heading")
				Verify.expect(Wire.field(seen.client, "author")):toBe("agent:claude")
				Verify.expect(last(inboxes, "b", "presence")):toBeNil()
				Server.receive(state, "a", Wire.encode({ type = "subscribe", file = "View.luau" }))
				local snapshot = last(inboxes, "a", "snapshot") :: Message
				Verify.expect(#Wire.list(snapshot.presence)):toBe(1)
				Server.disconnect(state, "b")
				local left = last(inboxes, "a", "presence") :: Message
				Verify.expect(left.left):toBe(true)
			end,
		})

		verifyHarness:case("broadcasts external text edits and invalid source found by polling", {
			id = "lute/design_server::Design server::broadcasts external text edits and invalid source found by polling",
			run = function(test)
				local state, inboxes, path, directory = hub("external")
				test:defer(function()
					Fixtures.remove(directory)
				end)
				join(state, "a", "alice", "human")
				Server.receive(state, "a", Wire.encode({ type = "subscribe", file = "View.luau" }))
				local edited = string.gsub(Fixtures.SMALL, '"Hello"', '"Edited in an editor"')
				task.wait(0.05)
				fs.writeStringToFile(path, edited)
				Server.poll(state)
				local update = last(inboxes, "a", "update") :: Message
				Verify.expect(update.author):toBe("external")
				Verify.expect(update.hash):toBe(Workspace.hash(edited))
				Verify.expect(update.valid):toBe(true)
				task.wait(0.05)
				fs.writeStringToFile(path, edited .. "\nreturn (")
				Server.poll(state)
				local invalid = last(inboxes, "a", "invalid") :: Message
				Verify.expect(type(invalid.error)):toBe("string")
				Server.receive(
					state,
					"a",
					Wire.encode({
						type = "apply",
						file = "View.luau",
						base = invalid.hash,
						ops = { { op = "remove", node = "Go" } },
					})
				)
				local rejected = last(inboxes, "a", "rejected") :: Message
				Verify.expect(Wire.field(rejected.error, "message")):toContain("does not parse")
			end,
		})

		verifyHarness:case("routes generic tool calls and broadcasts their document changes", {
			id = "lute/design_server::Design server::routes generic tool calls and broadcasts their document changes",
			run = function(test)
				local state, inboxes, _, directory = hub("tool")
				test:defer(function()
					Fixtures.remove(directory)
				end)
				join(state, "a", "alice", "human")
				join(state, "b", "claude", "agent")
				Server.receive(state, "a", Wire.encode({ type = "subscribe", file = "View.luau" }))
				Server.receive(
					state,
					"b",
					Wire.encode({
						type = "tool",
						request = "t",
						name = "insert",
						input = { file = "View.luau", parent = "Screen", node = { kind = "Divider", label = "Rule" } },
					})
				)
				local reply = last(inboxes, "b", "result") :: Message
				Verify.expect(reply.ok):toBe(true)
				local update = last(inboxes, "a", "update") :: Message
				Verify.expect(update.author):toBe("agent:claude")
				Verify.expect(update.source):toContain('UI.Divider "Rule" {}')
				Server.receive(
					state,
					"b",
					Wire.encode({
						type = "tool",
						name = "comment_add",
						input = { file = "View.luau", node = "Rule", text = "Thicker?" },
					})
				)
				local note = last(inboxes, "a", "comments") :: Message
				Verify.expect(note.author):toBe("agent:claude")
			end,
		})

		verifyHarness:case("serves HTTP status and a WebSocket session on a local port", {
			id = "lute/design_server::Design server::serves HTTP status and a WebSocket session on a local port",
			run = function(test)
				local path = Fixtures.file("socket", Fixtures.SMALL)
				local directory = string.match(path, "^(.*)/[^/]+$") :: string
				local running =
					Server.start({ root = directory, port = 0, schema = schema, interval = 0.05, version = "test" })
				test:defer(function()
					running.stop()
					Fixtures.remove(directory)
				end)
				local port = running.server.port
				local status = net.client.request(("http://127.0.0.1:%d/status"):format(port))
				Verify.expect(status.status):toBe(200)
				local _, body = Wire.decode(status.body)
				Verify.expect(Wire.field(body, "name")):toBe("facet-design")
				local received: { Message } = {}
				local socket = net.client.websocket(("ws://127.0.0.1:%d/ws"):format(port), {
					onmessage = function(message: string | buffer)
						local text = if type(message) == "string" then message else buffer.tostring(message)
						local ok, decoded = Wire.decode(text)
						if ok then
							table.insert(received, decoded :: Message)
						end
					end,
				})
				test:defer(function()
					pcall(function()
						socket:close()
					end)
				end)
				local function waitFor(kind: string): Message
					for _ = 1, 200 do
						for _, message in received do
							if message.type == kind then
								return message
							end
						end
						task.wait(0.01)
					end
					error("no " .. kind .. " message", 2)
				end
				task.wait(0.05)
				socket:send(Wire.encode({ type = "hello", client = { name = "probe", kind = "plugin" } }))
				waitFor("welcome")
				socket:send(Wire.encode({ type = "subscribe", file = "View.luau" }))
				local snapshot = waitFor("snapshot")
				socket:send(Wire.encode({
					type = "apply",
					file = "View.luau",
					base = snapshot.hash,
					ops = { { op = "set_prop", node = "Go", prop = "label", value = "Live" } },
				}))
				local update = waitFor("update")
				Verify.expect(update.author):toBe("plugin:probe")
				Verify.expect(fs.readFileToString(path)):toContain('label = "Live"')
				local tree = net.client.request(("http://127.0.0.1:%d/tree?file=View.luau"):format(port))
				Verify.expect(tree.status):toBe(200)
				Verify.expect(tree.body):toContain('label = \\"Live\\"')
			end,
		})
	end)
end
