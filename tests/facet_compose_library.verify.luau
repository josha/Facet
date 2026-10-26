--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	local Facet = require("../src")
	local Design = require("../src/vendor/compose/design")
	local engines = require("./lib/native_engine")
	local session = require("../tools/designer/modules/session")
	local composeLibrary = require("../tools/designer/modules/compose_library")
	local designerLibrary = require("../tools/designer/modules/library")

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

	local function mount(render: (ctx: composeLibrary.Context) -> unknown)
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
		return session.mount(Facet, parent, { name = "Library", render = render }, options), parent
	end

	local function documentWith(names: { string }, library: Design.Library): Design.Document
		local nextId = 2
		local function seeded(seed: { [string]: any }): Design.Node
			local props: { [string]: Design.Value } = {}
			for key, value in seed.props or {} do
				props[key] = { literal = value }
			end
			local node: Design.Node = { id = `n{nextId}`, kind = seed.kind, name = seed.kind, props = props, children = {} }
			nextId += 1
			for _, child in seed.children or {} do
				table.insert(node.children, seeded(child))
			end
			return node
		end
		local children: { Design.Node } = {}
		for _, name in names do
			local definition = designerLibrary.definitions[name]
			local seeds = definition.seeds
				or if library.kinds[name].children ~= "none"
					then { { kind = "Text", props = { text = "Make this content yours" } } }
					else {}
			table.insert(children, seeded({ kind = name, children = seeds }))
		end
		return {
			schema = "compose-design/1",
			name = "Every control",
			library = library.name,
			nextId = nextId,
			contract = { inputs = {}, outputs = {} },
			root = { id = "n1", kind = "ScrollView", name = "Root", props = {}, children = children },
		}
	end

	verifyHarness:suite("Facet library in Compose Design", function()
		verifyHarness:case("describes every designer control as a Compose Design kind", {
			id = "facet_compose_library::describes every designer control as a Compose Design kind",
			run = function()
				local library = composeLibrary.create({
					Facet = Facet,
					Compose = Facet.Compose,
					runtime = nil,
					Host = nil,
					UI = {},
				})
				local names = designerLibrary.names()
				Verify.expect(#names):toBeGreaterThan(60)
				for _, name in names do
					local kind = library.kinds[name]
					Verify.expect(kind ~= nil):toBe(true)
					Verify.expect(kind.call):toBe("UI." .. name)
				end
			end,
		})

		verifyHarness:case("renders every Facet control through Compose Design", {
			id = "facet_compose_library::renders every Facet control through Compose Design",
			run = function()
				local built: { [string]: boolean } = {}
				local mounted = mount(function(ctx: composeLibrary.Context)
					local library = composeLibrary.create(ctx)
					local names = designerLibrary.names()
					return Design.render(documentWith(names, library), library, {
						decorate = function(node: Design.Node, instance: unknown)
							if instance ~= nil then
								built[node.kind] = true
							end
						end,
					})
				end)
				for _, name in designerLibrary.names() do
					Verify.expect(`{name} {built[name] == true}`):toBe(`{name} true`)
				end
				mounted.dispose()
			end,
		})

		verifyHarness:case("emits Facet source for a design that uses every control", {
			id = "facet_compose_library::emits Facet source for a design that uses every control",
			run = function()
				local library = composeLibrary.create({
					Facet = Facet,
					Compose = Facet.Compose,
					runtime = nil,
					Host = nil,
					UI = {},
				})
				local code = Design.emit(documentWith(designerLibrary.names(), library), library)
				for _, name in designerLibrary.names() do
					Verify.expect(string.find(code, `UI.{name} "{name}"`, 1, true) ~= nil):toBe(true)
				end
			end,
		})
	end)
end
