--!strict
local Verify = require("../../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local fs = require("@std/fs")
	local Comments = require("../../tools/facet/design/comments")
	local Registry = require("../../tools/facet/design/registry")
	local Wire = require("../../tools/facet/design/wire")
	local Workspace = require("../../tools/facet/design/workspace")
	local Fixtures = require("./design_fixtures")

	local schema = Fixtures.schema()

	local function setup(label: string, source: string): (string, string, Registry.Context)
		local path = Fixtures.file(label, source)
		local directory = string.match(path, "^(.*)/[^/]+$") :: string
		return path, directory, { author = "human:alice", root = directory, schema = schema }
	end

	local function call(context: Registry.Context, name: string, input: { [string]: unknown }): { [string]: unknown }
		local result, failure = Registry.call(context, name, input)
		if result == nil then
			error(name .. " failed: " .. (failure :: Registry.Failure).message, 2)
		end
		return result :: { [string]: unknown }
	end

	local function threads(context: Registry.Context, node: string?, resolved: boolean?): { { [string]: unknown } }
		local query: { [string]: unknown } = { file = "View.luau", node = node, resolved = resolved }
		return call(context, "comment_list", query).threads :: { { [string]: unknown } }
	end

	verifyHarness:suite("Design comments", function()
		verifyHarness:case("adds, replies to, resolves and lists threads in the sidecar file", {
			id = "lute/design_comments::Design comments::adds, replies to, resolves and lists threads in the sidecar file",
			run = function(test)
				local path, directory, context = setup("comments", Fixtures.SMALL)
				test:defer(function()
					Fixtures.remove(directory)
				end)
				local added =
					call(context, "comment_add", { file = "View.luau", node = "Heading", text = "Use a warmer title." })
				local thread = added.thread :: { [string]: unknown }
				Verify.expect(thread.id):toBe("t1")
				Verify.expect(thread.node):toBe("Screen/Heading")
				local agent: Registry.Context = { author = "agent:claude", root = directory, schema = schema }
				call(
					agent,
					"comment_reply",
					{ file = "View.luau", thread = "t1", text = "Changed it to Welcome home." }
				)
				call(context, "comment_resolve", { file = "View.luau", thread = "t1" })
				local listed = threads(context)
				Verify.expect(#listed):toBe(1)
				local messages = listed[1].messages :: { { [string]: unknown } }
				Verify.expect(#messages):toBe(2)
				Verify.expect(messages[1].author):toBe("human:alice")
				Verify.expect(messages[2].author):toBe("agent:claude")
				Verify.expect(listed[1].resolved):toBe(true)
				Verify.expect(listed[1].orphaned):toBe(false)
				Verify.expect(#threads(context, nil, false)):toBe(0)
				local stored = fs.readFileToString(Workspace.commentsPath(path))
				local ok, decoded = Wire.decode(stored)
				Verify.expect(ok):toBe(true)
				Verify.expect(Wire.field(decoded, "version")):toBe(1)
				Verify.expect(Wire.field(decoded, "next")):toBe(2)
				Verify.expect(fs.readFileToString(path)):toBe(Fixtures.SMALL)
			end,
		})

		verifyHarness:case("keeps anchors on nodes that are renamed, moved and wrapped", {
			id = "lute/design_comments::Design comments::keeps anchors on nodes that are renamed, moved and wrapped",
			run = function(test)
				local _, directory, context = setup("anchors", Fixtures.RICH)
				test:defer(function()
					Fixtures.remove(directory)
				end)
				call(context, "comment_add", { file = "View.luau", node = "Left", text = "Check contrast." })
				call(context, "comment_add", { file = "View.luau", node = "Close", text = "Rename the button." })
				call(context, "rename", { file = "View.luau", node = "Row", label = "Split" })
				call(context, "move", { file = "View.luau", node = "Close", parent = "Split" })
				call(
					context,
					"wrap",
					{ file = "View.luau", node = "Root/Panel/Split", kind = "VStack", label = "Group" }
				)
				local listed = threads(context)
				Verify.expect(listed[1].node):toBe("Root/Panel/Group/Split/Left")
				Verify.expect(listed[2].node):toBe("Root/Panel/Group/Split/Close")
				Verify.expect(listed[1].orphaned):toBe(false)
				Verify.expect(listed[2].orphaned):toBe(false)
				Verify.expect(#threads(context, "Root/Panel/Group")):toBe(2)
			end,
		})

		verifyHarness:case("marks a thread orphaned when its node is removed", {
			id = "lute/design_comments::Design comments::marks a thread orphaned when its node is removed",
			run = function(test)
				local _, directory, context = setup("orphan", Fixtures.SMALL)
				test:defer(function()
					Fixtures.remove(directory)
				end)
				call(context, "comment_add", { file = "View.luau", node = "Go", text = "Remove this?" })
				call(context, "remove", { file = "View.luau", node = "Go" })
				local listed = threads(context)
				Verify.expect(listed[1].orphaned):toBe(true)
				Verify.expect(listed[1].node):toBe("Screen/Go")
			end,
		})

		verifyHarness:case("refuses empty text, unknown threads and unknown nodes", {
			id = "lute/design_comments::Design comments::refuses empty text, unknown threads and unknown nodes",
			run = function(test)
				local _, directory, context = setup("refusals", Fixtures.SMALL)
				test:defer(function()
					Fixtures.remove(directory)
				end)
				local _, empty = Registry.call(context, "comment_add", { file = "View.luau", node = "Go", text = "" })
				Verify.expect((empty :: Registry.Failure).message):toContain("1 to 4000 bytes")
				local _, missing =
					Registry.call(context, "comment_reply", { file = "View.luau", thread = "t9", text = "Hello" })
				Verify.expect((missing :: Registry.Failure).message):toContain("no comment thread t9")
				local _, node =
					Registry.call(context, "comment_add", { file = "View.luau", node = "Nowhere", text = "Hello" })
				Verify.expect((node :: Registry.Failure).message):toContain("no node Nowhere")
			end,
		})

		verifyHarness:case("remaps nested anchors by id prefix", {
			id = "lute/design_comments::Design comments::remaps nested anchors by id prefix",
			run = function()
				local store = Comments.empty()
				Comments.add(store, "Root/Panel", "a", "human:a", 1)
				Comments.add(store, "Root/Panel/Title", "b", "human:a", 1)
				Comments.add(store, "Root/Panelist", "c", "human:a", 1)
				Verify.expect(Comments.remap(store, { { from = "Root/Panel", to = "Root/Box" } })):toBe(true)
				Verify.expect(store.threads[1].node):toBe("Root/Box")
				Verify.expect(store.threads[2].node):toBe("Root/Box/Title")
				Verify.expect(store.threads[3].node):toBe("Root/Panelist")
				local decoded = Comments.decode(Comments.encode(store)) :: Comments.Store
				Verify.expect(#decoded.threads):toBe(3)
				Verify.expect(decoded.next):toBe(4)
			end,
		})
	end)
end
