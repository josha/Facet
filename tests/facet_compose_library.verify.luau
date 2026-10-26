--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Facet = require("../src")
	local FacetDesign = require("../src/design")
	local Design = Facet.Design
	local engines = require("./lib/native_engine")
	local session = require("../tools/designer/modules/session")

	type Types = {
		Color3: {
			fromRGB: (r: number, g: number, b: number) -> unknown,
			new: (r: number, g: number, b: number) -> unknown,
		},
		UDim2: {
			new: (xScale: number, xOffset: number, yScale: number, yOffset: number) -> unknown,
			fromOffset: (x: number, y: number) -> unknown,
		},
		UDim: { new: (scale: number, offset: number) -> unknown },
		Vector2: { new: (x: number, y: number) -> unknown },
		Vector3: { new: (x: number, y: number, z: number) -> unknown },
		CFrame: { new: (...number) -> unknown },
		Font: { new: (family: string, weight: unknown) -> unknown },
		Enum: { [string]: { [string]: unknown } },
	}
	type Context = { UI: Facet.Controls, types: Types, runtime: Facet.Runtime }
	type Engine = typeof(engines.new())

	local function config()
		return {
			width = 1280,
			height = 720,
			input = "Touch",
			display = "Small",
			distance = "near",
			palette = "Dark",
			textSize = "Medium",
			motionLevel = "none",
		}
	end

	local function mount(render: (ctx: Context, engine: Engine) -> unknown)
		local engine = engines.new()
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		engine.environment.poke(input, "PreferredInput", engine.types.Enum.PreferredInput.KeyboardAndMouse)
		input.GetFocusedTextBox = function()
			return nil
		end
		local options = {
			config = config(),
			engine = engine,
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
		}
		local parent = engine.new("ScreenGui")
		return session.mount(Facet, parent, {
			name = "Library",
			render = function(ctx: Context)
				return render(ctx, engine)
			end,
		}, options)
	end

	local function names(): { string }
		local list: { string } = {}
		for name in Facet.designControls do
			table.insert(list, name)
		end
		table.sort(list)
		return list
	end

	local function offline(): Facet.DesignLibrary
		return Facet.designLibrary({
			UI = {},
			rgb = function(r: number, g: number, b: number): unknown
				return { r, g, b }
			end,
			udim2 = function(a: number, b: number, c: number, d: number): unknown
				return { a, b, c, d }
			end,
			offset = function(x: number, y: number): unknown
				return { 0, x, 0, y }
			end,
		})
	end

	local function live(ctx: Context): Facet.DesignLibrary
		return Facet.designLibrary({
			UI = ctx.UI,
			rgb = ctx.types.Color3.fromRGB,
			udim2 = ctx.types.UDim2.new,
			offset = ctx.types.UDim2.fromOffset,
		})
	end

	local function documentWith(kinds: { string }, library: Facet.DesignLibrary): Facet.DesignDocument
		local nextId = 2
		local function seeded(seed: Facet.DesignSeed): Facet.DesignNode
			local props: { [string]: Facet.DesignValue } = {}
			local literals = seed.props
			if literals ~= nil then
				for key, value in literals do
					props[key] = { literal = value }
				end
			end
			local node: Facet.DesignNode =
				{ id = `n{nextId}`, kind = seed.kind, name = `{seed.kind}{nextId}`, props = props, children = {} }
			nextId += 1
			local nested = seed.children
			if nested ~= nil then
				for _, child in nested do
					table.insert(node.children, seeded(child))
				end
			end
			return node
		end
		local children: { Facet.DesignNode } = {}
		for _, name in kinds do
			if library.kinds[name].children == "template" then
				local list = seeded({ kind = name })
				list.bind = { from = "rows", key = "id" }
				local row = seeded({ kind = "Text" })
				row.props.text = { item = "label" }
				table.insert(list.children, row)
				table.insert(children, list)
				continue
			end
			table.insert(children, seeded({ kind = name, children = Facet.designSeeds(name) }))
		end
		local first: { [string]: Facet.DesignLiteral } = { id = "a", label = "First" }
		local second: { [string]: Facet.DesignLiteral } = { id = "b", label = "Second" }
		local idField: Facet.DesignItemField = { id = "id", type = "string" }
		local labelField: Facet.DesignItemField = { id = "label", type = "string" }
		local preview: Facet.DesignLiteral = { first, second }
		local rows: Facet.DesignInput = {
			id = "rows",
			kind = "value",
			type = "list",
			preview = preview,
			fields = { idField, labelField },
		}
		return {
			schema = "compose-design/1",
			name = "Every control",
			library = library.name,
			nextId = nextId,
			contract = { inputs = { rows }, outputs = {} },
			root = { id = "n1", kind = "ScrollView", name = "Root", props = {}, children = children },
		}
	end

	verifyHarness:suite("Facet library in Compose Design", function()
		verifyHarness:case("describes every Facet control as a Compose Design kind", {
			id = "facet_compose_library::describes every Facet control as a Compose Design kind",
			run = function()
				local library = offline()
				local list = names()
				Verify.expect(Facet.designControls == FacetDesign.controls):toBe(true)
				Verify.expect(#list):toBeGreaterThan(60)
				for _, name in list do
					Verify.expect(library.kinds[name].call):toBe("UI." .. name)
					Verify.expect(library.kinds[name].category ~= nil):toBe(true)
				end
			end,
		})

		verifyHarness:case("inserts every Facet control with its defaults into a valid design", {
			id = "facet_compose_library::inserts every Facet control with its defaults into a valid design",
			run = function()
				local library = offline()
				local failures: { string } = {}
				for _, name in names() do
					local ok, problem = pcall(function()
						local value = Design.document.new("Probe", library, "VStack")
						Design.document.insert(value, library, "n1", name)
					end)
					if not ok then
						table.insert(failures, `{name}: {problem}`)
					end
				end
				Verify.expect(table.concat(failures, "\n")):toBe("")
			end,
		})

		verifyHarness:case("renders every Facet control through Compose Design", {
			id = "facet_compose_library::renders every Facet control through Compose Design",
			run = function()
				local built: { [string]: boolean } = {}
				local misnamed: { string } = {}
				local mounted = mount(function(ctx: Context)
					local library = live(ctx)
					return Design.render(documentWith(names(), library), library, {
						decorate = function(node: Facet.DesignNode, instance: unknown)
							if typeof(instance) == "Instance" then
								built[node.kind] = true
								local named = instance.Name
								if named ~= node.name and named ~= node.name .. "Host" then
									table.insert(misnamed, `{node.kind}: {named} ~= {node.name}`)
								end
							elseif instance ~= nil then
								built[node.kind] = true
							end
						end,
					})
				end)
				for _, name in names() do
					Verify.expect(`{name} {built[name] == true}`):toBe(`{name} true`)
				end
				Verify.expect(table.concat(misnamed, "\n")):toBe("")
				mounted.dispose()
			end,
		})

		verifyHarness:case("edits a Facet design in the Compose design editor", {
			id = "facet_compose_library::edits a Facet design in the Compose design editor",
			run = function()
				local DesignEditor = require("../src/vendor/compose/design-editor")
				local editor: DesignEditor.Editor? = nil
				local mounted = mount(function(ctx: Context, engine: Engine)
					local types = ctx.types
					local library = live(ctx)
					local environment = Facet.Roblox.designEnvironment({
						service = function(name: string): unknown
							return engine.new(name)
						end,
						values = {
							vector2 = types.Vector2.new,
							vector3 = types.Vector3.new,
							udim = types.UDim.new,
							udim2 = types.UDim2.new,
							color = types.Color3.new,
							font = function(family: string, weight: string): unknown
								return types.Font.new(family, types.Enum.FontWeight[weight])
							end,
							enum = function(name: string, item: string): unknown
								return types.Enum[name][item]
							end,
							cframe = function(components: { number }): unknown
								return types.CFrame.new(table.unpack(components))
							end,
							raycastParams = function(): unknown
								return nil
							end,
						},
					})
					local host = ctx.UI.VStack("Editor")({ width = "fill" })
					editor = DesignEditor.create(library, Design.document.new("Shop", library, "VStack"), host, {
						runtime = ctx.runtime,
						environment = environment,
						stageSize = { X = 480, Y = 320 },
					})
					return host
				end)
				local opened = assert(editor)
				Verify.expect(opened.session.insert("Button")):toBe(true)
				Verify.expect(opened.session.change("label", { literal = "Buy" })):toBe(true)
				local value = opened.session.document:peek()
				local found = assert(Design.document.find(value.root, opened.session.selected:peek()))
				Verify.expect(found.kind):toBe("Button")
				Verify.expect(found.props.label.literal):toBe("Buy")
				Verify.expect(string.find(Design.emit(value, opened.session.library), 'label = "Buy"', 1, true) ~= nil)
					:toBe(true)
				opened.dispose()
				mounted.dispose()
			end,
		})

		verifyHarness:case("authors whole game views with typed props, outputs and Roblox values", {
			id = "facet_compose_library::authors whole game views with typed props, outputs and Roblox values",
			run = function()
				local library = Facet.designLibrary({
					UI = {},
					rgb = function(r: number, g: number, b: number): unknown
						return { r, g, b }
					end,
					udim2 = function(a: number, b: number, c: number, d: number): unknown
						return { a, b, c, d }
					end,
					offset = function(x: number, y: number): unknown
						return { 0, x, 0, y }
					end,
					host = function(className: string, name: string, props: { [unknown]: unknown }): unknown
						return { className = className, name = name, props = props }
					end,
				})
				local rowFields: { Facet.DesignItemField } =
					{ { id = "id", type = "string" }, { id = "title", type = "string" } }
				local retryArgs: { Facet.DesignInputType } = {}
				local retry: Facet.DesignOutput = { id = "onRetry", args = retryArgs }
				local value = Design.document.new("ChooseGameView", library, "VStack")
				value = Design.document.setContract(value, library, {
					inputs = {
						{ id = "name", kind = "value", type = "string", required = true },
						{ id = "games", kind = "readable", type = "list", fields = rowFields },
						{ id = "offered", kind = "readable", type = "boolean" },
					},
					outputs = { retry },
				})
				value = Design.document.nameFromInput(value, library, "n1", "name")
				local size: Facet.DesignLiteral = { 1, 0, 0, 320 }
				value = Design.document.change(value, library, "n1", "Size", { literal = size })
				value = Design.document.change(value, library, "n1", "AutomaticSize", { literal = "Y" })
				local list, row, button
				value, list = Design.document.insert(value, library, "n1", "VStack")
				value, row = Design.document.insert(value, library, list, "Text")
				value = Design.document.bind(value, library, list, { from = "games", key = "id" })
				value = Design.document.change(value, library, row, "text", { item = "title" })
				value, button = Design.document.insert(value, library, "n1", "Button")
				local badge
				value, badge = Design.document.insert(value, library, button, "Text")
				value = Design.document.change(value, library, badge, "text", { literal = "3 new" })
				value = Design.document.change(value, library, button, "onActivate", { output = "onRetry" })
				value = Design.document.change(value, library, button, "selected", { literal = true })
				value = Design.document.showWhen(value, library, button, "offered")
				local code = Design.emit(value, library, {
					name = "ChooseGameView",
					controls = "local UI = Facet.controls(runtime)",
				})
				for _, expected in
					{
						"local function ChooseGameView(props: Props): GuiObject",
						"UI.VStack(props.name) {",
						"Size = UDim2.new(1, 0, 0, 320)",
						"AutomaticSize = Enum.AutomaticSize.Y",
						"from = props.games,",
						"Facet.Compose.show(props.offered, function()",
						"if props.onRetry then",
						'UI.Text "Text" {',
						"games: Facet.Compose.ReadOnlyValue<{ { id: string, title: string } }>?",
						"\tname: string,",
					}
				do
					Verify.expect(`{expected} {string.find(code, expected, 1, true) ~= nil}`):toBe(`{expected} true`)
				end
				Verify.expect(Design.emit(Design.parse(code, library), library, {
					name = "ChooseGameView",
					controls = "local UI = Facet.controls(runtime)",
				})):toBe(code)

				local panel = Design.document.new("MatchmakingPanel", library, "Frame")
				panel = Design.document.change(panel, library, "n1", "BackgroundTransparency", { literal = 1 })
				local inner
				panel, inner = Design.document.insert(panel, library, "n1", "Text")
				panel = Design.document.change(panel, library, inner, "text", { literal = "Finding players" })
				Verify.expect(string.find(Design.emit(panel, library), 'Host.Frame "Frame" {', 1, true) ~= nil)
					:toBe(true)
			end,
		})

		verifyHarness:case("accepts the literals Facet controls take at runtime", {
			id = "facet_compose_library::accepts the literals Facet controls take at runtime",
			run = function()
				local library = offline()
				local value = Design.document.new("Drawer", library, "VStack")
				value = Design.document.change(value, library, "n1", "gap", { literal = 8 })
				local sideTable: { [string | number]: Facet.DesignLiteral } = { left = 8, right = 8, top = 12 }
				local sides: Facet.DesignLiteral = sideTable
				value = Design.document.change(value, library, "n1", "padding", { literal = sides })
				local text, sheet, alert
				value, text = Design.document.insert(value, library, "n1", "Text")
				value = Design.document.change(value, library, text, "textSize", { literal = "body" })
				value = Design.document.change(value, library, text, "TextColor3", { literal = "#986325" })
				value, sheet = Design.document.insert(value, library, "n1", "Sheet")
				value = Design.document.change(value, library, sheet, "closeButton", { literal = "Cancel" })
				local reportArgs: { Facet.DesignInputType } = {}
				local report: Facet.DesignOutput = { id = "onReport", args = reportArgs }
				value = Design.document.setContract(value, library, { inputs = {}, outputs = { report } })
				value, alert = Design.document.insert(value, library, "n1", "Alert")
				local call: { [string | number]: Facet.DesignLiteral } = {}
				call["$output"] = "onReport"
				local action: { [string | number]: Facet.DesignLiteral } = { id = "report", label = "Report" }
				action.onActivate = call
				local actions: Facet.DesignLiteral = { action }
				value = Design.document.change(value, library, alert, "actions", { literal = actions })
				local picker
				value, picker = Design.document.insert(value, library, "n1", "Picker")
				local option: { [string | number]: Facet.DesignLiteral } = { value = "Medium", label = "Standard" }
				local pickerOptions: Facet.DesignLiteral = { option }
				value = Design.document.change(value, library, picker, "options", { literal = pickerOptions })
				local emitOptions: Facet.DesignEmitOptions = {
					name = "Drawer",
					rowFunctions = true,
					controls = "local UI = Facet.controls(runtime)",
					localControls = true,
				}
				local code = Design.emit(value, library, emitOptions)
				for _, expected in
					{
						"gap = 8,",
						"local vStackPadding: Facet.Sides = { left = 8, right = 8, top = 12 }",
						"padding = vStackPadding,",
						"local UI = Facet.controls(runtime)",
						'textSize = "body",',
						'TextColor3 = Color3.fromHex "986325",',
						'closeButton = "Cancel",',
						"if props.onReport then",
					}
				do
					Verify.expect(`{expected} {string.find(code, expected, 1, true) ~= nil}`):toBe(`{expected} true`)
				end
				Verify.expect(Design.emit(Design.parse(code, library), library, emitOptions)):toBe(code)
			end,
		})

		verifyHarness:case("emits Facet source for a design that uses every control", {
			id = "facet_compose_library::emits Facet source for a design that uses every control",
			run = function()
				local library = offline()
				local code = Design.emit(documentWith(names(), library), library, { name = "EveryControl" })
				for _, name in names() do
					Verify.expect(string.find(code, `UI.{name} "{name}%d+"`) ~= nil):toBe(true)
				end
				Verify.expect(Design.parse(code, library).root.kind):toBe("ScrollView")
			end,
		})
	end)
end
