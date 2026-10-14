--!strict
local Verify = require("../../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local fs = require("@std/fs")
	local Workspace = require("../../tools/facet/design/workspace")
	local Wire = require("../../tools/facet/design/wire")
	local Fixtures = require("./design_fixtures")

	local schema = Fixtures.schema()
	local ALICE: Workspace.Options = { author = "human:alice" }
	local AGENT: Workspace.Options = { author = "agent:claude" }

	local function setup(label: string, source: string?): (string, string)
		local path = Fixtures.file(label, source or Fixtures.SMALL)
		return path, string.match(path, "^(.*)/[^/]+$") :: string
	end

	local function read(path: string): string
		return fs.readFileToString(path)
	end

	local function apply(path: string, ops: { unknown }, options: Workspace.Options): Workspace.Applied
		local applied, failure = Workspace.apply(path, ops, options, schema)
		if applied == nil then
			error((failure :: Workspace.Failure).code .. ": " .. (failure :: Workspace.Failure).message, 2)
		end
		return applied :: Workspace.Applied
	end

	verifyHarness:suite("Design workspace", function()
		verifyHarness:case("writes nothing when a later operation in the batch fails", {
			id = "lute/design_workspace::Design workspace::writes nothing when a later operation in the batch fails",
			run = function(context)
				local path, directory = setup("atomic")
				context:defer(function()
					Fixtures.remove(directory)
				end)
				local ops: { unknown } = {
					{ op = "set_prop", node = "Heading", prop = "text", value = "Changed" },
					{ op = "insert", parent = "Screen", node = { kind = "Text", props = { text = "New" } } },
					{ op = "remove", node = "Missing" },
				}
				local applied, failure = Workspace.apply(path, ops, ALICE, schema)
				Verify.expect(applied):toBeNil()
				Verify.expect((failure :: Workspace.Failure).code):toBe("invalid")
				Verify.expect((failure :: Workspace.Failure).message):toContain("operation 3 (remove): no node Missing")
				Verify.expect(read(path)):toBe(Fixtures.SMALL)
				Verify.expect(fs.exists(Workspace.historyPath(path))):toBe(false)
			end,
		})

		verifyHarness:case("checks every input before it applies any operation", {
			id = "lute/design_workspace::Design workspace::checks every input before it applies any operation",
			run = function(context)
				local path, directory = setup("validate")
				context:defer(function()
					Fixtures.remove(directory)
				end)
				local ops: { unknown } = {
					{ op = "set_prop", node = "Heading", prop = "text", value = "Changed" },
					{ op = "set_prop", node = "Heading" },
				}
				local _, failure = Workspace.apply(path, ops, ALICE, schema)
				Verify.expect((failure :: Workspace.Failure).message)
					:toContain("operation 2 (set_prop).prop is required")
				local _, unknown = Workspace.apply(path, { { op = "explode" } }, ALICE, schema)
				Verify.expect((unknown :: Workspace.Failure).message):toContain("explode is not a document operation")
				local _, empty = Workspace.apply(path, {}, ALICE, schema)
				Verify.expect((empty :: Workspace.Failure).message):toContain("at least one operation")
				Verify.expect(read(path)):toBe(Fixtures.SMALL)
			end,
		})

		verifyHarness:case("rejects a batch made against a stale base hash", {
			id = "lute/design_workspace::Design workspace::rejects a batch made against a stale base hash",
			run = function(context)
				local path, directory = setup("stale")
				context:defer(function()
					Fixtures.remove(directory)
				end)
				local base = Workspace.hash(Fixtures.SMALL)
				local first = apply(path, { { op = "set_prop", node = "Heading", prop = "text", value = "One" } }, {
					author = "human:alice",
					base = base,
				})
				Verify.expect(first.previous):toBe(base)
				local _, failure = Workspace.apply(
					path,
					{ { op = "set_prop", node = "Heading", prop = "text", value = "Two" } },
					{
						author = "agent:claude",
						base = base,
					},
					schema
				)
				Verify.expect((failure :: Workspace.Failure).code):toBe("stale")
				Verify.expect((failure :: Workspace.Failure).message):toContain(first.hash)
				Verify.expect(read(path)):toContain('text = "One"')
			end,
		})

		verifyHarness:case("lets an author undo only its own entries", {
			id = "lute/design_workspace::Design workspace::lets an author undo only its own entries",
			run = function(context)
				local path, directory = setup("owner")
				context:defer(function()
					Fixtures.remove(directory)
				end)
				local human =
					apply(path, { { op = "set_prop", node = "Heading", prop = "text", value = "Human" } }, ALICE)
				apply(path, { { op = "set_prop", node = "Go", prop = "label", value = "Agent" } }, AGENT)
				local _, forbidden = Workspace.undo(path, { author = "agent:claude", entry = human.entry }, schema)
				Verify.expect((forbidden :: Workspace.Failure).code):toBe("forbidden")
				local undone = Workspace.undo(path, ALICE, schema)
				Verify.expect(undone ~= nil):toBe(true)
				local text = read(path)
				Verify.expect(text):toContain('text = "Hello"')
				Verify.expect(text):toContain('label = "Agent"')
				local _, nothing = Workspace.undo(path, ALICE, schema)
				Verify.expect((nothing :: Workspace.Failure).code):toBe("not_found")
				local agentUndo = Workspace.undo(path, AGENT, schema)
				Verify.expect(agentUndo ~= nil):toBe(true)
				Verify.expect(read(path)):toBe(Fixtures.SMALL)
				local history = Workspace.history(path)
				Verify.expect(#history):toBe(4)
			end,
		})

		verifyHarness:case("redoes undone edits in reverse order and clears redo after a new edit", {
			id = "lute/design_workspace::Design workspace::redoes undone edits in reverse order and clears redo after a new edit",
			run = function(context)
				local path, directory = setup("redo")
				context:defer(function()
					Fixtures.remove(directory)
				end)
				apply(path, { { op = "set_prop", node = "Heading", prop = "text", value = "One" } }, ALICE)
				local one = read(path)
				apply(path, { { op = "set_prop", node = "Heading", prop = "text", value = "Two" } }, ALICE)
				local two = read(path)
				Workspace.undo(path, ALICE, schema)
				Workspace.undo(path, ALICE, schema)
				Verify.expect(read(path)):toBe(Fixtures.SMALL)
				Workspace.redo(path, ALICE, schema)
				Verify.expect(read(path)):toBe(one)
				Workspace.redo(path, ALICE, schema)
				Verify.expect(read(path)):toBe(two)
				local _, none = Workspace.redo(path, ALICE, schema)
				Verify.expect((none :: Workspace.Failure).code):toBe("not_found")
				Workspace.undo(path, ALICE, schema)
				apply(path, { { op = "set_prop", node = "Go", prop = "label", value = "Fresh" } }, ALICE)
				local _, cleared = Workspace.redo(path, ALICE, schema)
				Verify.expect((cleared :: Workspace.Failure).code):toBe("not_found")
			end,
		})

		verifyHarness:case("refuses an undo when another author changed the same node", {
			id = "lute/design_workspace::Design workspace::refuses an undo when another author changed the same node",
			run = function(context)
				local path, directory = setup("conflict")
				context:defer(function()
					Fixtures.remove(directory)
				end)
				apply(path, { { op = "set_prop", node = "Heading", prop = "text", value = "Mine" } }, ALICE)
				apply(path, { { op = "set_prop", node = "Heading", prop = "text", value = "Theirs" } }, AGENT)
				local before = read(path)
				local _, failure = Workspace.undo(path, ALICE, schema)
				Verify.expect((failure :: Workspace.Failure).code):toBe("conflict")
				Verify.expect((failure :: Workspace.Failure).message):toContain("changed after this edit")
				Verify.expect(read(path)):toBe(before)
			end,
		})

		verifyHarness:case("undoes a structural edit while another author edits elsewhere", {
			id = "lute/design_workspace::Design workspace::undoes a structural edit while another author edits elsewhere",
			run = function(context)
				local path, directory = setup("interleaved", Fixtures.RICH)
				context:defer(function()
					Fixtures.remove(directory)
				end)
				apply(path, { { op = "wrap", nodes = { "Title", "Row" }, kind = "VStack", label = "Header" } }, ALICE)
				apply(path, { { op = "set_prop", node = "Close", prop = "label", value = "Done" } }, AGENT)
				local undone = Workspace.undo(path, ALICE, schema)
				Verify.expect(undone ~= nil):toBe(true)
				local expected = string.gsub(Fixtures.RICH, 'label = "Close"', 'label = "Done"')
				Verify.expect(read(path)):toBe(expected)
			end,
		})

		verifyHarness:case("records history entries with authors and exact inverse operations", {
			id = "lute/design_workspace::Design workspace::records history entries with authors and exact inverse operations",
			run = function(context)
				local path, directory = setup("history")
				context:defer(function()
					Fixtures.remove(directory)
				end)
				local applied = apply(path, {
					{
						op = "insert",
						parent = "Screen",
						node = { kind = "Text", label = "Body", props = { text = "Body" } },
					},
					{ op = "rename", node = "Go", label = "Start" },
				}, AGENT)
				local raw = read(Workspace.historyPath(path))
				local ok, decoded = Wire.decode(raw)
				Verify.expect(ok):toBe(true)
				local entries = Wire.list(Wire.field(decoded, "entries"))
				Verify.expect(#entries):toBe(1)
				local entry = entries[1]
				Verify.expect(Wire.field(entry, "author")):toBe("agent:claude")
				Verify.expect(Wire.field(entry, "kind")):toBe("edit")
				Verify.expect(Wire.field(entry, "id")):toBe(applied.entry)
				Verify.expect(Wire.field(entry, "base")):toBe(Workspace.hash(Fixtures.SMALL))
				Verify.expect(Wire.field(entry, "result")):toBe(applied.hash)
				local inverse = Wire.list(Wire.field(entry, "inverse"))
				Verify.expect(#inverse):toBe(2)
				Verify.expect(Wire.field(inverse[1], "op")):toBe("restore_label")
				Verify.expect(Wire.field(inverse[2], "op")):toBe("restore_entries")
			end,
		})

		verifyHarness:case("refuses an author name with unsupported characters", {
			id = "lute/design_workspace::Design workspace::refuses an author name with unsupported characters",
			run = function(context)
				local path, directory = setup("author")
				context:defer(function()
					Fixtures.remove(directory)
				end)
				local _, failure = Workspace.apply(
					path,
					{ { op = "remove", node = "Go" } },
					{ author = "bad author" },
					schema
				)
				Verify.expect((failure :: Workspace.Failure).code):toBe("invalid")
				Verify.expect(read(path)):toBe(Fixtures.SMALL)
			end,
		})

		verifyHarness:case("finds view modules and skips other Luau files", {
			id = "lute/design_workspace::Design workspace::finds view modules and skips other Luau files",
			run = function(context)
				local path, directory = setup("discover")
				context:defer(function()
					Fixtures.remove(directory)
				end)
				fs.writeStringToFile(directory .. "/helper.luau", "return { value = 1 }\n")
				local found = Workspace.discover({ directory })
				Verify.expect(found):toEqual({ path })
			end,
		})
	end)
end
