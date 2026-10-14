--!strict
local Verify = require("../../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Document = require("../../tools/facet/design/document")
	local Operations = require("../../tools/facet/design/operations")
	local Fixtures = require("./design_fixtures")

	type Doc = Document.Document
	type Scenario = {
		name: string,
		source: string,
		ops: { unknown },
		check: (Doc, string) -> (),
	}

	local schema = Fixtures.schema()

	local function contains(text: string, needle: string)
		Verify.expect(text):toContain(needle)
	end

	local function node(doc: Doc, id: string): Document.Node
		local found = doc.nodes[id]
		if found == nil then
			local ids: { string } = {}
			for key in doc.nodes do
				table.insert(ids, key)
			end
			table.sort(ids)
			error("no node " .. id .. "; nodes are " .. table.concat(ids, ", "), 2)
		end
		return found :: Document.Node
	end

	local function childIds(doc: Doc, id: string): { string }
		local ids: { string } = {}
		for _, child in node(doc, id).children do
			table.insert(ids, child.id)
		end
		return ids
	end

	local function propText(doc: Doc, id: string, name: string): string?
		local prop = Document.prop(node(doc, id), name)
		return if prop then prop.value.text else nil
	end

	local scenarios: { Scenario } = {
		{
			name = "set_prop replaces an existing literal",
			source = Fixtures.RICH,
			ops = { { op = "set_prop", node = "Close", prop = "label", value = "Done" } },
			check = function(doc: Doc, text: string)
				Verify.expect(propText(doc, "Root/Panel/Close", "label")):toBe('"Done"')
				contains(text, '\t\t\t\tlabel = "Done",\n')
			end,
		},
		{
			name = "set_prop adds a literal union in sorted order with the file cast style",
			source = Fixtures.SMALL,
			ops = { { op = "set_prop", node = "Heading", prop = "textAlign", value = "center" } },
			check = function(_doc: Doc, text: string)
				contains(
					text,
					'text = "Hello",\n\t\t\ttextAlign = "center" :: "center",\n\t\t\ttextRole = "title" :: "title",\n'
				)
			end,
		},
		{
			name = "set_prop expands a one-line table that no longer fits",
			source = Fixtures.RICH,
			ops = { { op = "set_prop", node = "Row", prop = "align", value = "center" } },
			check = function(doc: Doc, text: string)
				contains(
					text,
					'\t\t\tUI.HStack "Row" {\n\t\t\t\talign = "center" :: "center",\n\t\t\t\tgap = "s",\n\t\t\t\tUI.Text "Left" { text = "A" },\n\t\t\t\tUI.Text "Right" { text = "B" },\n\t\t\t},\n'
				)
				Verify.expect(childIds(doc, "Root/Panel/Row"))
					:toEqual({ "Root/Panel/Row/Left", "Root/Panel/Row/Right" })
			end,
		},
		{
			name = "set_prop writes datatype, enum and table values",
			source = Fixtures.RICH,
			ops = {
				{
					op = "set_prop",
					node = "Close",
					prop = "Size",
					value = { kind = "datatype", type = "UDim2", constructor = "fromScale", args = { 1, 0.5 } },
				},
				{
					op = "set_prop",
					node = "Panel",
					prop = "AutomaticSize",
					value = { kind = "enum", enum = "AutomaticSize", item = "Y" },
				},
				{
					op = "set_prop",
					node = "Panel",
					prop = "padding",
					value = { kind = "table", fields = { top = 8, bottom = 8 } },
				},
			},
			check = function(doc: Doc, _text: string)
				Verify.expect(propText(doc, "Root/Panel/Close", "Size")):toBe("UDim2.fromScale(1, 0.5)")
				Verify.expect(propText(doc, "Root/Panel", "AutomaticSize")):toBe("Enum.AutomaticSize.Y")
				Verify.expect(propText(doc, "Root/Panel", "padding")):toBe("{ bottom = 8, top = 8 }")
				local padding = (Document.prop(node(doc, "Root/Panel"), "padding") :: Document.Prop).value
				Verify.expect(padding.kind):toBe("table")
			end,
		},
		{
			name = "unset_prop removes a property line",
			source = Fixtures.RICH,
			ops = { { op = "unset_prop", node = "Close", prop = "Size" } },
			check = function(doc: Doc, text: string)
				Verify.expect(Document.prop(node(doc, "Root/Panel/Close"), "Size")):toBeNil()
				Verify.expect((string.find(text, "UDim2", 1, true))):toBeNil()
			end,
		},
		{
			name = "insert adds a control with an automatic label at a position",
			source = Fixtures.RICH,
			ops = {
				{
					op = "insert",
					parent = "Panel",
					index = 0,
					node = { kind = "Text", props = { text = "Inventory", textRole = "caption" } },
				},
				{
					op = "insert",
					parent = "Panel",
					before = "Close",
					node = { kind = "Text", props = { text = "Second" } },
				},
			},
			check = function(doc: Doc, text: string)
				local ids = childIds(doc, "Root/Panel")
				Verify.expect(ids[1]):toBe("Root/Panel/Text")
				Verify.expect(ids[#ids - 1]):toBe("Root/Panel/Text2")
				contains(
					text,
					'\t\t\tUI.Text "Text" {\n\t\t\t\ttext = "Inventory",\n\t\t\t\ttextRole = "caption" :: "caption",\n\t\t\t},\n'
				)
				local token = (Document.prop(node(doc, "Root/Panel/Text"), "textRole") :: Document.Prop).value
				Verify.expect(token.kind):toBe("token")
				Verify.expect(token.set):toBe("typography")
			end,
		},
		{
			name = "insert adds nested children and a keyed collection",
			source = Fixtures.RICH,
			ops = {
				{
					op = "insert",
					parent = "Panel",
					node = {
						kind = "HStack",
						label = "Actions",
						props = { gap = "s" },
						children = {
							{ kind = "Button", props = { label = "Save" } },
							{ kind = "Button", props = { label = "Load" } },
						},
					},
				},
				{
					op = "insert",
					parent = "Panel",
					node = {
						keyed = {
							from = "items",
							key = "id",
							template = {
								kind = "Text",
								label = "Entry",
								props = { text = { kind = "binding", source = "item", path = "name" } },
							},
						},
					},
				},
			},
			check = function(doc: Doc, text: string)
				Verify.expect(childIds(doc, "Root/Panel/Actions"))
					:toEqual({ "Root/Panel/Actions/Button", "Root/Panel/Actions/Button2" })
				local keyed = node(doc, "Root/Panel/Entry[]")
				Verify.expect(keyed.type):toBe("keyed")
				Verify.expect(keyed.keyField):toBe("id")
				local template = node(doc, "Root/Panel/Entry[]/Entry")
				local binding = (Document.prop(template, "text") :: Document.Prop).value
				Verify.expect(binding.kind):toBe("binding")
				Verify.expect(binding.source):toBe("item")
				Verify.expect(binding.path):toBe("name")
				contains(
					text,
					"\t\t\tCompose.keyed({\n\t\t\t\tfrom = model.items,\n\t\t\t\tkey = function(item)\n\t\t\t\t\treturn item.id\n\t\t\t\tend,\n"
				)
			end,
		},
		{
			name = "remove deletes a node with its line",
			source = Fixtures.RICH,
			ops = { { op = "remove", node = "Root/Panel/#Divider1" } },
			check = function(doc: Doc, text: string)
				Verify.expect(doc.nodes["Root/Panel/#Divider1"]):toBeNil()
				Verify.expect((string.find(text, "Divider", 1, true))):toBeNil()
			end,
		},
		{
			name = "move reparents a node and keeps its long string bytes",
			source = Fixtures.RICH,
			ops = { { op = "move", node = "Notes", parent = "Row", index = 0 } },
			check = function(doc: Doc, text: string)
				Verify.expect(childIds(doc, "Root/Panel/Row")[1]):toBe("Root/Panel/Row/Notes")
				contains(
					text,
					'\t\t\t\tUI.Text "Notes" {\n\t\t\t\t\ttext = [[\nFirst line\n\tSecond line]],\n\t\t\t\t\twrap = true,\n\t\t\t\t},\n'
				)
			end,
		},
		{
			name = "move reorders siblings and carries leading comments",
			source = Fixtures.RICH,
			ops = { { op = "move", node = "Title", parent = "Panel", after = "Close" } },
			check = function(doc: Doc, text: string)
				local ids = childIds(doc, "Root/Panel")
				Verify.expect(ids[#ids]):toBe("Root/Panel/Title")
				contains(text, '\t\t\t},\n\t\t\t-- The title follows the model.\n\t\t\tUI.Text "Title" {\n')
			end,
		},
		{
			name = "wrap puts adjacent siblings in a new container",
			source = Fixtures.RICH,
			ops = {
				{ op = "wrap", nodes = { "Title", "Row" }, kind = "VStack", label = "Header", props = { gap = "xs" } },
			},
			check = function(doc: Doc, text: string)
				Verify.expect(childIds(doc, "Root/Panel/Header"))
					:toEqual({ "Root/Panel/Header/Title", "Root/Panel/Header/Row" })
				contains(
					text,
					'\t\t\tUI.VStack "Header" {\n\t\t\t\tgap = "xs",\n\t\t\t\t-- The title follows the model.\n\t\t\t\tUI.Text "Title" {\n\t\t\t\t\ttext = function(use)\n\t\t\t\t\t\treturn use(model.title)\n'
				)
			end,
		},
		{
			name = "wrap replaces the root with a container",
			source = Fixtures.SMALL,
			ops = { { op = "wrap", node = "Screen", kind = "ZStack", label = "Layers" } },
			check = function(doc: Doc, text: string)
				Verify.expect((doc.root :: Document.Node).id):toBe("Layers")
				Verify.expect(childIds(doc, "Layers")):toEqual({ "Layers/Screen" })
				contains(text, '\treturn UI.ZStack "Layers" {\n\t\tUI.Screen "Screen" {\n\t\t\tgap = "m",\n')
			end,
		},
		{
			name = "unwrap moves children into the parent",
			source = Fixtures.RICH,
			ops = { { op = "unwrap", node = "Row" } },
			check = function(doc: Doc, text: string)
				local ids = childIds(doc, "Root/Panel")
				Verify.expect(ids[2]):toBe("Root/Panel/Left")
				Verify.expect(ids[3]):toBe("Root/Panel/Right")
				contains(text, '\t\t\tUI.Text "Left" { text = "A" },\n\t\t\tUI.Text "Right" { text = "B" },\n')
			end,
		},
		{
			name = "rename changes a label and adds a label to an unlabeled control",
			source = Fixtures.RICH,
			ops = {
				{ op = "rename", node = "Title", label = "Heading" },
				{ op = "rename", node = "Root/Panel/#Divider1", label = "Rule" },
			},
			check = function(doc: Doc, text: string)
				Verify.expect(doc.nodes["Root/Panel/Heading"] ~= nil):toBe(true)
				Verify.expect(doc.nodes["Root/Panel/Rule"] ~= nil):toBe(true)
				contains(text, 'UI.Divider "Rule" {},')
			end,
		},
		{
			name = "bind writes a model binding and rebinds a collection source",
			source = Fixtures.RICH,
			ops = {
				{ op = "bind", node = "Close", prop = "label", path = "labels.close" },
				{ op = "bind", node = "Root/Panel/Item[]", prop = "from", path = "inventory" },
			},
			check = function(doc: Doc, text: string)
				local value = (Document.prop(node(doc, "Root/Panel/Close"), "label") :: Document.Prop).value
				Verify.expect(value.kind):toBe("binding")
				Verify.expect(value.path):toBe("labels.close")
				contains(
					text,
					"\t\t\t\tlabel = function(use)\n\t\t\t\t\treturn use(model.labels.close)\n\t\t\t\tend,\n"
				)
				contains(text, "\t\t\t\tfrom = model.inventory,\n")
			end,
		},
		{
			name = "unbind replaces a binding with a literal",
			source = Fixtures.RICH,
			ops = { { op = "unbind", node = "Title", prop = "text", value = "Inventory" } },
			check = function(doc: Doc, _text: string)
				Verify.expect(propText(doc, "Root/Panel/Title", "text")):toBe('"Inventory"')
			end,
		},
		{
			name = "set_token writes a theme token",
			source = Fixtures.RICH,
			ops = { { op = "set_token", node = "Panel", prop = "gap", token = "l" } },
			check = function(doc: Doc, text: string)
				local value = (Document.prop(node(doc, "Root/Panel"), "gap") :: Document.Prop).value
				Verify.expect(value.kind):toBe("token")
				Verify.expect(value.set):toBe("space")
				contains(text, 'gap = "l", -- tight rows')
			end,
		},
		{
			name = "duplicate inserts a relabeled copy after the node",
			source = Fixtures.RICH,
			ops = { { op = "duplicate", node = "Close" } },
			check = function(doc: Doc, text: string)
				local ids = childIds(doc, "Root/Panel")
				Verify.expect(ids[#ids]):toBe("Root/Panel/Close2")
				contains(text, 'UI.Button "Close2" {\n\t\t\t\tlabel = "Close",\n')
			end,
		},
		{
			name = "insert follows space indentation",
			source = Fixtures.SPACES,
			ops = { { op = "insert", parent = "Screen", node = { kind = "Divider", label = "Rule" } } },
			check = function(_doc: Doc, text: string)
				contains(text, '        },\n        UI.Divider "Rule" {},\n    }\n')
			end,
		},
	}

	local function run(scenario: Scenario): (Doc, Operations.BatchResult)
		local doc = Document.parse(scenario.source, schema)
		local result, problem = Operations.apply(doc, schema, scenario.ops)
		if result == nil then
			error(scenario.name .. ": " .. tostring(problem), 2)
		end
		return doc, result :: Operations.BatchResult
	end

	verifyHarness:suite("Design operations", function()
		for _, scenario in scenarios do
			verifyHarness:case(scenario.name, {
				id = "lute/design_operations::Design operations::" .. scenario.name,
				run = function()
					local _, result = run(scenario)
					scenario.check(result.doc, result.doc.source)
					local undone, problem =
						Operations.apply(result.doc, schema, Operations.restoreOps(result.inverse), true)
					Verify.expect(problem):toBeNil()
					Verify.expect((undone :: Operations.BatchResult).doc.source == scenario.source):toBe(true)
				end,
			})
		end

		verifyHarness:case("every scenario result passes stylua --check", {
			id = "lute/design_operations::Design operations::every scenario result passes stylua --check",
			requires = { "stylua" },
			run = function()
				for _, scenario in scenarios do
					if scenario.source ~= Fixtures.SPACES then
						local _, result = run(scenario)
						local clean, output = Fixtures.stylua(result.doc.source)
						Verify.expect(clean):toBeTrueWith(scenario.name .. "\n" .. output)
					end
				end
			end,
		})
	end)

	type Refusal = { name: string, source: string, ops: { unknown }, message: string }

	local refusals: { Refusal } = {
		{
			name = "an unknown property",
			source = Fixtures.SMALL,
			ops = { { op = "set_prop", node = "Heading", prop = "colour", value = "red" } },
			message = "Text has no property colour",
		},
		{
			name = "a value of the wrong type",
			source = Fixtures.SMALL,
			ops = { { op = "set_prop", node = "Heading", prop = "text", value = 42 } },
			message = "Text.text takes",
		},
		{
			name = "a literal outside its union",
			source = Fixtures.SMALL,
			ops = { { op = "set_prop", node = "Heading", prop = "textAlign", value = "middle" } },
			message = "Text.textAlign takes",
		},
		{
			name = "a binding on a static property",
			source = Fixtures.SMALL,
			ops = { { op = "bind", node = "Heading", prop = "truncate", path = "mode" } },
			message = "cannot take a binding",
		},
		{
			name = "removing a required property",
			source = Fixtures.SMALL,
			ops = { { op = "unset_prop", node = "Heading", prop = "text" } },
			message = "Text requires text",
		},
		{
			name = "an unknown control",
			source = Fixtures.SMALL,
			ops = { { op = "insert", parent = "Screen", node = { kind = "Widget" } } },
			message = "unknown control Widget",
		},
		{
			name = "a missing required property",
			source = Fixtures.SMALL,
			ops = { { op = "insert", parent = "Screen", node = { kind = "Grid" } } },
			message = "Grid needs columns",
		},
		{
			name = "a duplicate sibling label",
			source = Fixtures.SMALL,
			ops = {
				{ op = "insert", parent = "Screen", node = { kind = "Text", label = "Go", props = { text = "x" } } },
			},
			message = "already used by a sibling",
		},
		{
			name = "removing the root",
			source = Fixtures.SMALL,
			ops = { { op = "remove", node = "Screen" } },
			message = "cannot be removed",
		},
		{
			name = "moving a node into itself",
			source = Fixtures.RICH,
			ops = { { op = "move", node = "Panel", parent = "Row" } },
			message = "cannot move inside itself",
		},
		{
			name = "wrapping siblings that are not adjacent",
			source = Fixtures.RICH,
			ops = { { op = "wrap", nodes = { "Title", "Close" }, kind = "VStack" } },
			message = "adjacent",
		},
		{
			name = "unwrapping a root with several children",
			source = Fixtures.SMALL,
			ops = { { op = "unwrap", node = "Screen" } },
			message = "exactly one child",
		},
		{
			name = "an unknown theme token",
			source = Fixtures.SMALL,
			ops = { { op = "set_token", node = "Screen", prop = "gap", token = "huge" } },
			message = "use l, m, s, xl, xs",
		},
		{
			name = "a token on a property without tokens",
			source = Fixtures.SMALL,
			ops = { { op = "set_token", node = "Go", prop = "label", token = "m" } },
			message = "takes no theme tokens",
		},
		{
			name = "duplicating a collection template",
			source = Fixtures.RICH,
			ops = { { op = "duplicate", node = "Root/Panel/Item[]/Item" } },
			message = "cannot be duplicated",
		},
		{
			name = "an unknown node",
			source = Fixtures.SMALL,
			ops = { { op = "remove", node = "Missing" } },
			message = "no node Missing",
		},
		{
			name = "an internal operation",
			source = Fixtures.SMALL,
			ops = { { op = "restore_expr", node = "Screen", text = "x", expect = "y" } },
			message = "not a document operation",
		},
		{
			name = "an input field the operation does not declare",
			source = Fixtures.SMALL,
			ops = { { op = "remove", node = "Go", extra = true } },
			message = "unknown field extra",
		},
	}

	verifyHarness:suite("Design operation refusals", function()
		for _, refusal in refusals do
			verifyHarness:case("refuses " .. refusal.name, {
				id = "lute/design_operations::Design operation refusals::refuses " .. refusal.name,
				run = function()
					local doc = Document.parse(refusal.source, schema)
					local result, problem = Operations.apply(doc, schema, refusal.ops)
					Verify.expect(result):toBeNil()
					Verify.expect(problem or ""):toContain(refusal.message)
				end,
			})
		end
	end)
end
