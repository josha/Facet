--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Facet = require("../src")
	local engineFactory = require("./lib/native_engine")
	local document = require("../tools/designer/modules/document")
	local exporter = require("../tools/designer/modules/export")
	local source = require("../tools/designer/modules/source")
	local render = require("../tools/designer/modules/design_render")
	local session = require("../tools/designer/modules/session")
	local adapter = require("../tools/designer/modules/adapter")
	local library = require("../tools/designer/modules/library")
	local history = require("../tools/designer/modules/history")

	local function design(): (document.Document, string)
		local value, id = document.insert(document.new("Inventory"), "n1", "Table")
		value = document.change(
			value,
			id,
			"from",
			{ { id = "a", label = "Desk", score = 2 }, { id = "b", label = "Lamp", score = 0 } }
		)
		value = document.change(value, id, "dataKey", "Rows")
		value = document.change(value, id, "activationKey", "Choose")
		value = document.change(value, id, "rowActions", { { id = "choose", label = "Choose", handler = "Choose" } })
		value = document.columnTemplate(value, id, "label")
		return value, id
	end

	local function fixture(value: document.Document, setup: (any) -> ()): (any, any)
		local engine = engineFactory.new()
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		input.GetFocusedTextBox = function()
			return nil
		end
		local mounted = session.mount(Facet, engine.new("ScreenGui"), {
			name = "Bindings",
			render = function(ctx)
				setup(ctx)
				return render.build(value, ctx)
			end,
		}, {
			engine = engine,
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			config = {
				width = 700,
				height = 900,
				input = "KeyboardAndMouse",
				display = "Medium",
				distance = "near",
				palette = "Light",
				textSize = "Medium",
				motionLevel = "none",
			},
		})
		return mounted, engine
	end

	local function texts(root: Instance, name: string): { string }
		local result = {}
		for _, node in root:GetDescendants() do
			if node.Name == name and node:IsA("TextLabel") then
				table.insert(result, node.Text)
			end
		end
		table.sort(result)
		return result
	end

	verifyHarness:suite("Facet Design collection cells and bindings", function()
		verifyHarness:case("round-trips reusable cells, external data, activation, and actions", {
			id = "facet_design_bindings::Facet Design collection cells and bindings::round-trips reusable cells, external data, activation, and actions",
			run = function()
				local value, id = design()
				local cellId
				value, cellId = document.columnTemplate(value, id, "score")
				value = document.change(value, cellId, "name", "Quantity cell")
				local textId = assert(document.find(value.root, cellId)).children[1].id
				value = document.remove(value, textId)
				local badge
				value, badge = document.insert(value, cellId, "Badge")
				value = document.change(value, badge, "labelField", "score")
				local code = exporter.component(value)
				local parsed = source.parse(code, value.name)
				Verify.expect((exporter.component(parsed))):toBe(code)
				local tableNode = assert(document.find(parsed.root, "n2"))
				Verify.expect(tableNode.props.dataKey):toBe("Rows")
				Verify.expect(tableNode.props.activationKey):toBe("Choose")
				Verify.expect(tableNode.props.rowActions[1].handler):toBe("Choose")
				Verify.expect(tableNode.children[2].name):toBe("Quantity cell")
				Verify.expect(tableNode.children[2].props.columnId):toBe("score")
			end,
		})
		verifyHarness:case("uses one visual structure with reactive data for distinct rows", {
			id = "facet_design_bindings::Facet Design collection cells and bindings::uses one visual structure with reactive data for distinct rows",
			run = function()
				local value = design()
				local rows: any
				local mounted, engine = fixture(value, function(ctx)
					rows = ctx.Compose.cell({
						{ id = "a", label = "Desk", score = 2 },
						{ id = "b", label = "Lamp", score = 0 },
					})
					ctx.data = { Rows = rows }
				end)
				local tableRoot = mounted.content:FindFirstChild("Table", true)
				tableRoot.AbsoluteSize = engine.types.Vector2.new(640, 240)
				tableRoot:FindFirstChild("Body").AbsoluteSize = engine.types.Vector2.new(640, 200)
				tableRoot:FindFirstChild("Body").AbsoluteWindowSize = engine.types.Vector2.new(640, 200)
				Verify.expect((table.concat(texts(mounted.content, "CellValue"), ","))):toBe("Desk,Lamp")
				rows:set({ { id = "b", label = "Lantern", score = 0 }, { id = "a", label = "Table", score = 3 } })
				Verify.expect((table.concat(texts(mounted.content, "CellValue"), ","))):toBe("Lantern,Table")
				mounted.dispose()
			end,
		})
		verifyHarness:case("dispatches named callbacks with the current row", {
			id = "facet_design_bindings::Facet Design collection cells and bindings::dispatches named callbacks with the current row",
			run = function()
				local value, id = design()
				local node = assert(document.find(value.root, id))
				local current = Facet.Compose.cell({ id = "a", label = "Desk" })
				local received: any
				local ctx = { data = {
					Choose = function(row)
						received = row
					end,
				} }
				local props = adapter.properties(node)
				local activate = adapter.evaluate(props.onActivate, ctx, {})
				activate(current:peek(), "a")
				Verify.expect(received.label):toBe("Desk")
				current:set({ id = "a", label = "Table" })
				adapter.evaluate(props.rowActions, ctx, {})(current).trailing[1].onActivate()
				Verify.expect(received.label):toBe("Table")
			end,
		})
		verifyHarness:case("keeps numeric zero and false fields and uses fallbacks for absent fields", {
			id = "facet_design_bindings::Facet Design collection cells and bindings::keeps numeric zero and false fields and uses fallbacks for absent fields",
			run = function()
				local current = Facet.Compose.cell({ count = 0, enabled = false })
				local locals = { current = current }
				local use = function(cell: any)
					return cell:peek()
				end
				local numeric = adapter.evaluate(
					adapter.expression("field", { key = "count", fallback = 9, conversion = "number" }),
					{},
					locals
				)
				local boolean = adapter.evaluate(
					adapter.expression("field", { key = "enabled", fallback = "missing", conversion = "string" }),
					{},
					locals
				)
				local missing = adapter.evaluate(
					adapter.expression("field", { key = "absent", fallback = "missing", conversion = "string" }),
					{},
					locals
				)
				Verify.expect((numeric(use))):toBe(0)
				Verify.expect((boolean(use))):toBe("false")
				Verify.expect((missing(use))):toBe("missing")
			end,
		})
		verifyHarness:case("supports a reusable VirtualList cell and row-local state", {
			id = "facet_design_bindings::Facet Design collection cells and bindings::supports a reusable VirtualList cell and row-local state",
			run = function()
				local value, id = document.insert(document.new("List"), "n1", "VirtualList")
				local cell
				value, cell = document.insert(value, id, "VStack")
				local label
				value, label = document.insert(value, cell, "Text")
				value = document.change(value, label, "textField", "label")
				value = document.insert(value, cell, "Toggle")
				local code = exporter.component(value)
				Verify.expect((exporter.component(source.parse(code, value.name)))):toBe(code)
				local before = string.match(code, "^(.-)return UI.Screen") or ""
				Verify.expect(string.find(before, "Compose.cell", 1, true) == nil):toBe(true)
				Verify.expect(string.find(code, "function(current: any)\nlocal state_", 1, true) ~= nil):toBe(true)
			end,
		})
		verifyHarness:case("rejects a binding outside a collection and duplicate column assignments", {
			id = "facet_design_bindings::Facet Design collection cells and bindings::rejects a binding outside a collection and duplicate column assignments",
			run = function()
				local value, id = document.insert(document.new(), "n1", "Text")
				Verify.expect((pcall(document.change, value, id, "textField", "name"))):toBe(false)
				Verify.expect((pcall(document.change, value, id, "columnId", "label"))):toBe(false)
				local inventory, tableId = design()
				local cell = assert(document.find(inventory.root, tableId)).children[1]
				local duplicate = document.copy(inventory)
				local copied = document.copy(cell)
				copied.id = "n99"
				copied.children[1].id = "n100"
				duplicate.nextId = 101
				table.insert(assert(document.find(duplicate.root, tableId)).children, copied)
				Verify.expect((pcall(document.validate, duplicate))):toBe(false)
			end,
		})
		verifyHarness:case("keeps bindings through undo and rejects executable source expressions", {
			id = "facet_design_bindings::Facet Design collection cells and bindings::keeps bindings through undo and rejects executable source expressions",
			run = function()
				local value, id = design()
				local child = assert(document.find(value.root, id)).children[1].children[1].id
				local stack = history.new(value)
				stack.commit(document.change(value, child, "textField", "score"), child)
				stack.undo()
				Verify.expect((exporter.component(stack.current()))):toBe(exporter.component(value))
				local code = exporter.component(value)
				Verify.expect(
					(pcall(source.parse, string.gsub(code, 'use%(current%)%["label"%]', "stealData()"), value.name))
				)
					:toBe(false)
				Verify.expect(
					(
						pcall(
							library.parse,
							library.descriptor("Table", "rowActions"),
							{ { id = "x", label = "X", onActivate = "code" } }
						)
					)
				):toBe(false)
			end,
		})
	end)
end
