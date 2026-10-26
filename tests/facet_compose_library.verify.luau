--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Facet = require("../src")
	local FacetDesign = require("../src/design")
	local Kit = Facet.design()
	local Design = Kit.Design
	local engines = require("./lib/native_engine")

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

	local function mount(render: (ctx: Context, engine: Engine) -> unknown): { dispose: () -> () }
		local engine = engines.new()
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		engine.environment.poke(input, "PreferredInput", engine.types.Enum.PreferredInput.KeyboardAndMouse)
		input.GetFocusedTextBox = function()
			return nil
		end
		local runtime = Facet.Roblox.createRuntime(engine)
		local UI = Facet.controls(runtime, {
			types = engine.types,
			services = { GuiService = gui, UserInputService = input },
			motionLevel = "none",
		})
		local stop = runtime.mount(function()
			return render({ UI = UI, types = engine.types, runtime = runtime }, engine)
		end, engine.new("ScreenGui"))
		return {
			dispose = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	local function designEnvironment(ctx: Context, engine: Engine)
		local types = ctx.types
		return Facet.Roblox.designEnvironment({
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
	end

	local function sample(field: Facet.DesignField, preset: Facet.DesignLiteral?): Facet.DesignValue?
		local kind = field.type
		local default = if preset ~= nil then preset else field.default
		if default ~= nil and kind ~= "node" and kind ~= "event" and kind ~= "content" then
			return { literal = default }
		elseif kind == "string" then
			return { literal = "Sample" }
		elseif kind == "number" then
			return { literal = 1 }
		elseif kind == "boolean" then
			return { literal = true }
		elseif kind == "choice" then
			local options = field.options
			return if options ~= nil and options[1] ~= nil then { literal = options[1] } else nil
		elseif kind == "color" then
			return { literal = "#336699" }
		elseif kind == "vector3" then
			return { literal = { 1, 2, 3 } }
		elseif kind == "node" then
			return { node = "n1" }
		end
		return nil
	end

	local function names(): { string }
		local list: { string } = {}
		for name in Kit.controls do
			table.insert(list, name)
		end
		table.sort(list)
		return list
	end

	local function offline(): Facet.DesignLibrary
		return Kit.library({
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
		return Kit.library({
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
			table.insert(children, seeded({ kind = name, children = Kit.seeds(name) }))
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
				Verify.expect(Kit.controls == FacetDesign.controls):toBe(true)
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
					local environment = designEnvironment(ctx, engine)
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

		verifyHarness:case("edits every field of every Facet control in the Compose design editor", {
			id = "facet_compose_library::edits every field of every Facet control in the Compose design editor",
			run = function()
				local DesignEditor = require("../src/vendor/compose/design-editor")
				local editor: DesignEditor.Editor? = nil
				local runtime: Facet.Runtime? = nil
				local mounted = mount(function(ctx: Context, engine: Engine)
					local library = live(ctx)
					runtime = ctx.runtime
					local host = ctx.UI.VStack("Editor")({ width = "fill" })
					editor = DesignEditor.create(library, Design.document.new("Every", library, "VStack"), host, {
						runtime = ctx.runtime,
						environment = designEnvironment(ctx, engine),
						stageSize = { X = 1280, Y = 720 },
					})
					return host
				end)
				local opened = assert(editor)
				local library = opened.session.library
				local failures: { string } = {}
				local edited = 0
				for _, name in names() do
					opened.session.replace(Design.document.new("Every", library, "VStack"))
					opened.session.select("n1")
					if not opened.session.insert(name) then
						table.insert(failures, `{name}: insert`)
						continue
					end
					local id = opened.session.selected:peek()
					local kind = library.kinds[name]
					local stage = assert(opened.stage)
					assert(runtime):settle()
					if stage.nodes[id] == nil then
						table.insert(failures, `{name}: {opened.session.problem:peek() or "not rendered"}`)
						continue
					end
					local keys: { string } = {}
					for key in kind.fields do
						table.insert(keys, key)
					end
					table.sort(keys)
					for _, key in keys do
						local defaults = kind.defaults
						local value = sample(kind.fields[key], if defaults then defaults[key] else nil)
						local field = kind.fields[key]
						local steps = 0
						local pending: { [string]: Facet.DesignValue } = {}
						local requires: { [string]: { Facet.DesignLiteral } } = field.requires or {}
						for other, allowed in requires do
							local needed = if #allowed > 0
								then { literal = allowed[1] }
								else sample(kind.fields[other], if defaults then defaults[other] else nil)
							if needed == nil then
								value = nil
							else
								pending[other] = needed
							end
						end
						local progressed = value ~= nil
						while progressed and next(pending) ~= nil do
							progressed = false
							for other, needed in pending do
								opened.session.select(id)
								if opened.session.change(other, needed) then
									steps += 1
									pending[other] = nil
									progressed = true
								end
							end
						end
						if value ~= nil then
							opened.session.select(id)
							local ok, changed = pcall(opened.session.change, key, value)
							assert(runtime):settle()
							if not ok or not changed then
								table.insert(
									failures,
									`{name}.{key}: {if ok then opened.session.problem:peek() else changed}`
								)
							elseif stage.nodes[id] == nil then
								table.insert(
									failures,
									`{name}.{key}: {opened.session.problem:peek() or "not rendered"}`
								)
							else
								edited += 1
							end
							if ok and changed then
								steps += 1
							end
						end
						for _ = 1, steps do
							opened.session.undo()
						end
					end
				end
				Verify.expect(table.concat(failures, "\n")):toBe("")
				Verify.expect(edited):toBeGreaterThan(900)
				opened.dispose()
				mounted.dispose()
			end,
		})

		verifyHarness:case("tags Facet controls for theme rules from Compose Design", {
			id = "facet_compose_library::tags Facet controls for theme rules from Compose Design",
			run = function()
				local tagged: Instance? = nil
				local mounted = mount(function(ctx: Context)
					local library = live(ctx)
					local value, id = Design.document.insert(
						Design.document.new("Tagged", library, "VStack"),
						library,
						"n1",
						"Button"
					)
					value = Design.document.tag(value, library, id, { "amigos-stat" })
					local code = Design.emit(value, library)
					Verify.expect(string.find(code, "Facet.tag(", 1, true) ~= nil):toBe(true)
					Verify.expect(Design.emit(Design.parse(code, library), library)):toBe(code)
					return Design.render(value, library, {
						decorate = function(node: Facet.DesignNode, instance: unknown)
							if node.id == id and typeof(instance) == "Instance" then
								tagged = instance
							end
						end,
					})
				end)
				Verify.expect(assert(tagged):HasTag("amigos-stat")):toBe(true)
				mounted.dispose()
			end,
		})

		verifyHarness:case("authors whole game views with typed props, outputs and Roblox values", {
			id = "facet_compose_library::authors whole game views with typed props, outputs and Roblox values",
			run = function()
				local library = Kit.library({
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
						"games: Facet.ReadOnlyValue<{ { id: string, title: string } }>?",
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

		verifyHarness:case("authors second-batch views with collection rows, statics and chosen nodes", {
			id = "facet_compose_library::authors second-batch views with collection rows, statics and chosen nodes",
			run = function()
				local library = offline()
				local rowFields: { Facet.DesignItemField } =
					{ { id = "revision", type = "string" }, { id = "word", type = "string" } }
				local value = Design.document.new("MatchHistory", library, "VStack")
				value = Design.document.setContract(value, library, {
					inputs = { { id = "turns", kind = "readable", type = "list", fields = rowFields } },
					outputs = {},
				})
				local list, row, empty
				value, list = Design.document.insert(value, library, "n1", "VirtualList")
				value = Design.document.bind(value, library, list, { from = "turns", key = "revision" })
				value, row = Design.document.insert(value, library, list, "Text")
				value = Design.document.change(value, library, row, "text", { item = "word" })
				value = Design.document.bind(value, library, list, { from = "turns", key = "revision", row = row })
				value = Design.document.change(value, library, list, "recycle", { literal = false })
				value = Design.document.change(value, library, list, "mode", { literal = "all" })
				value, empty = Design.document.insert(value, library, list, "Text")
				value = Design.document.rename(value, library, empty, "NoTurns")
				local code = Design.emit(value, library, { name = "MatchHistory", rowFunctions = true })
				for _, expected in { "recycle = false,", 'mode = "all",', 'UI.Text "NoTurns"' } do
					Verify.expect(`{expected} {string.find(code, expected, 1, true) ~= nil}`):toBe(`{expected} true`)
				end
				Verify.expect(
					Design.emit(Design.parse(code, library), library, { name = "MatchHistory", rowFunctions = true })
				)
					:toBe(code)
				local marker = Design.document.new("Rewards", library, "VStack")
				local markerState: Facet.DesignState = { id = "source", type = "string", initial = "Stage" }
				marker = Design.document.setState(marker, library, { markerState })
				local stage, flash
				marker, stage = Design.document.insert(marker, library, "n1", "VStack")
				marker = Design.document.rename(marker, library, stage, "Stage")
				marker, flash = Design.document.insert(marker, library, "n1", "WorldMarker")
				local anchorFields: { Facet.DesignItemField } = {}
				marker = Design.document.setContract(marker, library, {
					inputs = { { id = "anchor", kind = "readable", type = "record", fields = anchorFields } },
					outputs = {},
				})
				marker = Design.document.change(marker, library, flash, "anchor", { input = "anchor" })
				Verify.expect(string.find(Design.emit(marker, library), "anchor = props.anchor,", 1, true) ~= nil)
					:toBe(true)
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
