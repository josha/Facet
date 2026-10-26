--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Facet = require("../src")
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
				{ id = `n{nextId}`, kind = seed.kind, name = seed.kind, props = props, children = {} }
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
				local mounted = mount(function(ctx: Context)
					local library = live(ctx)
					return Design.render(documentWith(names(), library), library, {
						decorate = function(node: Facet.DesignNode, instance: unknown)
							if instance ~= nil then
								built[node.kind] = true
							end
						end,
					})
				end)
				for _, name in names() do
					Verify.expect(`{name} {built[name] == true}`):toBe(`{name} true`)
				end
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

		verifyHarness:case("emits Facet source for a design that uses every control", {
			id = "facet_compose_library::emits Facet source for a design that uses every control",
			run = function()
				local library = offline()
				local code = Design.emit(documentWith(names(), library), library, { name = "EveryControl" })
				for _, name in names() do
					Verify.expect(string.find(code, `UI.{name} "{name}"`, 1, true) ~= nil):toBe(true)
				end
				Verify.expect(Design.parse(code, library).root.kind):toBe("ScrollView")
			end,
		})
	end)
end
