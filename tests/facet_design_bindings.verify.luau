--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Facet = require("../src")
	local engineFactory = require("./lib/native_engine")
	local document = require("../tools/designer/modules/document")
	local render = require("../tools/designer/modules/design_render")
	local session = require("../tools/designer/modules/session")
	local adapter = require("../tools/designer/modules/adapter")

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
	end)
end
