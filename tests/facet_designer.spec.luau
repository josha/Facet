--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local catalog = require("../tools/designer/modules/catalog")
	local session = require("../tools/designer/modules/session")
	local document = require("../tools/designer/modules/document")
	local history = require("../tools/designer/modules/history")
	local library = require("../tools/designer/modules/library")
	local templates = require("../tools/designer/modules/templates")
	local exporter = require("../tools/designer/modules/export")
	local savedLibrary = require("../tools/designer/modules/saved_library")
	local source = require("../tools/designer/modules/source")
	local agent = require("../tools/designer/modules/agent")
	local transfer = require("../tools/designer/modules/transfer")
	local gallery = require("../tools/designer/modules/gallery")
	local serde = require("@lune/serde")
	local render = require("../tools/designer/modules/design_render")

	local function config()
		return {
			width = 390,
			height = 844,
			input = "Touch",
			display = "Small",
			distance = "near",
			palette = "Dark",
			textSize = "Medium",
			motionLevel = "none",
		}
	end

	local function fixture(render)
		local engine = engines.new()
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
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
		return session.mount(Facet, parent, { name = "Populated", render = render }, options), engine, parent
	end

	verifyHarness:suite("Facet Design documents and source", function()
		verifyHarness:case("has an adapter for every public control constructor", {
			id = "facet_designer::Facet Design documents and source::has an adapter for every public control constructor",
			run = function()
				local fs = require("@lune/fs")
				local sourceTypes = fs.readFile("src/ui/control_types.luau")
				local count = 0
				for name in string.gmatch(sourceTypes, "\n\t([A-Z][%w]+):") do
					count += 1
					Verify.expect(library.definitions[name] ~= nil):toBe(true)
				end
				Verify.expect(#library.names()):toBe(count)
			end,
		})
		verifyHarness:case("duplicates subtrees with unique IDs and rejects moves into descendants", {
			id = "facet_designer::Facet Design documents and source::duplicates subtrees with unique IDs and rejects moves into descendants",
			run = function()
				local value = document.copy(templates[1])
				local copied, id = document.duplicate(value, "n5")
				Verify.expect(#document.rows(copied.root)):toBe(13)
				Verify.expect(id):toBe("n10")
				Verify.expect(#document.rows(value.root)):toBe(9)
				Verify.expect(function()
					document.move(copied, "n10", "n11")
				end):toThrow()
				Verify.expect(function()
					document.remove(value, "n1")
				end):toThrow()
			end,
		})
		verifyHarness:case("reorders outline slots without losing subtrees or renames in undo", {
			id = "facet_designer::Facet Design documents and source::reorders outline slots without losing subtrees or renames in undo",
			run = function()
				local value = document.copy(templates[1])
				local moved = document.reorder(value, "n2", 3)
				Verify.expect(moved.root.children[3].id):toBe("n2")
				Verify.expect(document.reorder(moved, "n2", 1).root.children[1].id):toBe("n2")
				local subtree = document.reorder(value, "n5", 8)
				Verify.expect(subtree.root.children[#subtree.root.children].id):toBe("n5")
				Verify.expect(#assert(document.find(subtree.root, "n5")).children):toBe(3)
				Verify.expect((document.reorder(value, "n5", 4))):toBe(value)
				local nested = document.reorder(value, "n2", 5)
				Verify.expect(assert(select(2, document.find(nested.root, "n2"))).id):toBe("n5")
				Verify.expect(function()
					document.reorder(value, "n1", 1)
				end):toThrow()
				local stack = history.new(value)
				stack.commit(document.change(value, "n3", "name", "Trail heading"), "n3")
				Verify.expect(assert(document.find(stack.current().root, "n3")).name):toBe("Trail heading")
				stack.undo()
				Verify.expect(assert(document.find(stack.current().root, "n3")).name):toBe("Heading")
			end,
		})

		verifyHarness:case("restores selection with undo and invalidates redo after a new edit", {
			id = "facet_designer::Facet Design documents and source::restores selection with undo and invalidates redo after a new edit",
			run = function()
				local stack = history.new(document.new())
				local first, id = document.insert(stack.current(), "n1", "Text")
				stack.commit(first, id)
				stack.commit(document.change(first, id, "text", "Second"), id)
				stack.undo()
				local reverted, selected = stack.current()
				Verify.expect(selected):toBe(id)
				Verify.expect(assert(assert(document.find(reverted.root, id)).props).text):toBe("A little possibility")
				stack.undo()
				Verify.expect((select(2, stack.current()))):toBe("n1")
				stack.redo()
				stack.commit(document.change(stack.current(), id, "text", "Branch"), id)
				Verify.expect((stack.canRedo())):toBe(false)
			end,
		})
		verifyHarness:case("resets an edited property to its adapter default without losing undo", {
			id = "facet_designer::Facet Design documents and source::resets an edited property to its adapter default without losing undo",
			run = function()
				local value, id = document.insert(document.new(), "n1", "Text")
				local stack = history.new(value)
				stack.select(id)
				stack.commit(document.change(value, id, "text", "Edited title"), id)
				stack.commit(document.change(stack.current(), id, "text", nil), id)
				local reset = stack.current()
				Verify.expect(assert(assert(document.find(reset.root, id)).props).text):toBe(nil)
				Verify.expect(string.find(exporter.component(reset), 'text = "A little possibility"', 1, true) ~= nil)
					:toBe(true)
				stack.undo()
				Verify.expect(assert(assert(document.find(stack.current().root, id)).props).text):toBe("Edited title")
				stack.redo()
				Verify.expect(assert(assert(document.find(stack.current().root, id)).props).text):toBe(nil)
			end,
		})

		verifyHarness:case("renders every inspector preset and keeps its export stable", {
			id = "facet_designer::Facet Design documents and source::renders every inspector preset and keeps its export stable",
			run = function()
				local failures = {}
				for _, kind in library.names() do
					local value: any, id
					if kind == "Screen" then
						value, id = document.new(), "n1"
					else
						value, id = document.insert(document.new(), "n1", kind)
					end
					for _, field in library.definitions[kind].fields do
						if field.kind == "choice" or field.kind == "boolean" then
							for _, option in (if field.kind == "boolean" then { false, true } else field.options) do
								local ok, err = pcall(function()
									local edited = document.change(value, id, field.key, option)
									local code = exporter.component(edited)
									Verify.expect((exporter.component(source.parse(code, edited.name)))):toBe(code)
									local mounted = fixture(function(ctx)
										return render.build(edited, ctx)
									end)
									mounted.dispose()
								end)
								if not ok then
									table.insert(
										failures,
										kind
											.. "."
											.. field.key
											.. "="
											.. tostring(option)
											.. ": "
											.. (string.match(tostring(err), "[^\n]+") or tostring(err))
									)
								end
							end
						end
					end
				end
				assert(#failures == 0, table.concat(failures, "\n"))
			end,
		})

		verifyHarness:case("round trips every template through editable Luau", {
			id = "facet_designer::Facet Design documents and source::round trips every template through editable Luau",
			run = function()
				for _, value in templates do
					local code = exporter.component(value)
					local parsed = source.parse(code, value.name)
					Verify.expect((exporter.component(parsed))):toBe(code)
				end
			end,
		})
		verifyHarness:case("keeps literal code-looking text and rejects executable property expressions", {
			id = "facet_designer::Facet Design documents and source::keeps literal code-looking text and rejects executable property expressions",
			run = function()
				local value, id = document.insert(document.new(), "n1", "Text")
				value = document.change(value, id, "text", '"\n\\ UI.Button { label = "Injected" }\t🌲')
				local code = exporter.component(value)
				Verify.expect((exporter.component(source.parse(code, value.name)))):toBe(code)
				Verify.expect(function()
					source.parse(string.gsub(code, 'textRole = "body"', "textRole = getRole()"), value.name)
				end):toThrow()
			end,
		})
		verifyHarness:case("rejects cyclic documents, sparse children, unknown properties, and invalid choices", {
			id = "facet_designer::Facet Design documents and source::rejects cyclic documents, sparse children, unknown properties, and invalid choices",
			run = function()
				local value = document.new()
				value.root.children[1] = value.root
				Verify.expect(function()
					document.validate(value)
				end):toThrow()
				value = document.new()
				value.root.children[2] =
					{ id = "n2", kind = "Text" :: "Text", name = "Text", props = {}, children = {} }
				Verify.expect(function()
					document.validate(value)
				end):toThrow()
				value = document.new()
				value.root.props.bad = true
				Verify.expect(function()
					document.validate(value)
				end):toThrow()
				Verify.expect(function()
					library.parse(library.descriptor("Button", "appearance"), "unknown")
				end):toThrow()
			end,
		})
		for _, kind in library.names() do
			verifyHarness:case("exports and mounts " .. kind .. " using the current Facet API", {
				id = "facet_designer::"
					.. "Facet Design documents and source"
					.. "::"
					.. "exports and mounts "
					.. kind
					.. " using the current Facet API",
				run = function()
					local value = document.new()
					if kind ~= "Screen" then
						value = document.insert(value, "n1", kind)
					end
					local code = exporter.component(value)
					Verify.expect((exporter.component(source.parse(code, value.name)))):toBe(code)
					local mounted = fixture(function(ctx)
						return render.build(value, ctx)
					end)
					Verify.expect(mounted.content.Name):toBe("Screen")
					mounted.dispose()
				end,
			})
		end
	end)

	verifyHarness:suite("Facet Design browsing and transfer", function()
		verifyHarness:case("filters both titles and categories and bounds visual pages", {
			id = "facet_designer::Facet Design browsing and transfer::filters both titles and categories and bounds visual pages",
			run = function()
				local entries = {}
				for index = 1, 15 do
					table.insert(entries, {
						id = tostring(index),
						label = "Design " .. index,
						detail = if index % 2 == 0 then "Input" else "Layout",
					})
				end
				local page, pages = gallery.page(entries, "INPUT", 1)
				Verify.expect(#page):toBe(6)
				Verify.expect(pages):toBe(2)
				page = gallery.page(entries, "input", 10)
				Verify.expect(#page):toBe(1)
				Verify.expect(page[1].id):toBe("14")
				Verify.expect(#gallery.page(entries, "no matches", 1)):toBe(0)
			end,
		})
		verifyHarness:case("transfers editable designs without executable or unknown metadata", {
			id = "facet_designer::Facet Design browsing and transfer::transfers editable designs without executable or unknown metadata",
			run = function()
				local encode = function(value)
					return serde.encode("json", value)
				end
				local decode = function(text)
					return serde.decode("json", text)
				end
				for _, template in templates do
					local proposed = document.copy(template)
					proposed.metadata = { script = "do not execute" }
					local text = transfer.encode(proposed, encode)
					local imported = transfer.decode(text, decode)
					Verify.expect(imported.metadata):toBe(nil)
					Verify.expect((exporter.component(imported))):toBe(exporter.component(template))
				end
				Verify.expect(function()
					transfer.decode('{"format":"facet-design-file/2"}', decode)
				end):toThrow()
				Verify.expect(function()
					transfer.decode('{"format":"facet-design-file/1"}', decode)
				end):toThrow()
				Verify.expect(function()
					transfer.decode(string.rep("x", 900001), decode)
				end):toThrow()
				Verify.expect(function()
					transfer.decode('{"format":"facet-design-file/1","design":{}}', decode)
				end):toThrow()
			end,
		})
		verifyHarness:case("round trips side padding and explicit colors through code", {
			id = "facet_designer::Facet Design browsing and transfer::round trips side padding and explicit colors through code",
			run = function()
				local value =
					document.change(document.new(), "n1", "padding", { top = "m", right = 24, bottom = 8, left = "s" })
				value = document.change(value, "n1", "BackgroundColor3", "#143357")
				local code = exporter.component(value)
				Verify.expect((exporter.component(source.parse(code, value.name)))):toBe(code)
				local mounted = fixture(function(ctx)
					return render.build(value, ctx)
				end)
				mounted.dispose()
				Verify.expect(function()
					document.change(value, "n1", "padding", { center = 2 })
				end):toThrow()
				Verify.expect(function()
					document.change(value, "n1", "BackgroundTransparency", 2)
				end):toThrow()
			end,
		})
		verifyHarness:case("preserves document bounds and branch history over a long editing session", {
			id = "facet_designer::Facet Design browsing and transfer::preserves document bounds and branch history over a long editing session",
			run = function()
				local value, id = document.insert(document.new(), "n1", "Text")
				local stack = history.new(value)
				for index = 1, 150 do
					stack.commit(document.change(stack.current(), id, "text", "Revision " .. index), id)
					if index % 5 == 0 then
						stack.undo()
						stack.redo()
					end
				end
				Verify.expect(assert(assert(document.find(stack.current().root, id)).props).text):toBe("Revision 150")
				stack.undo()
				Verify.expect(assert(assert(document.find(stack.current().root, id)).props).text):toBe("Revision 149")
				stack.commit(document.change(stack.current(), id, "text", "New branch"), id)
				Verify.expect((stack.canRedo())):toBe(false)
			end,
		})
	end)

	verifyHarness:suite("Facet Design agent edits", function()
		verifyHarness:case("applies an atomic batch by layer name and keeps code visually editable", {
			id = "facet_designer::Facet Design agent edits::applies an atomic batch by layer name and keeps code visually editable",
			run = function()
				local code = exporter.component(templates[1])
				local generated, value = agent.patch(code, {
					{ op = "set", node = "Heading", property = "text", value = "An agent designed this" },
					{
						op = "set",
						node = "Preferences",
						property = "padding",
						value = { top = 16, right = 20, bottom = 16, left = 20 },
					},
					{ op = "set", node = "Explore", property = "appearance", value = "soft" },
				})
				Verify.expect((exporter.component(source.parse(generated, value.name)))):toBe(generated)
				Verify.expect(string.find(generated, "An agent designed this", 1, true) ~= nil):toBe(true)
				Verify.expect((exporter.component(templates[1]))):toBe(code)
				local mounted = fixture(function(ctx)
					return render.build(value, ctx)
				end)
				mounted.dispose()
			end,
		})
		verifyHarness:case("rejects invalid batches and custom source before changing anything", {
			id = "facet_designer::Facet Design agent edits::rejects invalid batches and custom source before changing anything",
			run = function()
				local value = document.copy(templates[1])
				Verify.expect(function()
					agent.apply(value, {
						{ op = "set", node = "Heading", property = "text", value = "Temporary" },
						{ op = "set", node = "Heading", property = "unknown", value = true },
					})
				end):toThrow()
				Verify.expect(assert(assert(document.find(value.root, "n3")).props).text)
					:toBe(templates[1].root.children[2].props.text)
				local code = exporter.component(value)
				Verify.expect(function()
					agent.patch(code .. "\ncustomGameLogic()", { { op = "remove", node = "Heading" } })
				end):toThrow()
			end,
		})
	end)

	verifyHarness:suite("Facet Design sessions", function()
		verifyHarness:case("updates device facts without remounting local state or native content", {
			id = "facet_designer::Facet Design sessions::updates device facts without remounting local state or native content",
			run = function()
				local builds, cleanup = 0, 0
				local value: any, env
				local mounted = fixture(function(ctx)
					builds += 1
					value = ctx.Compose.cell(7)
					env = ctx.UI.environment()
					ctx.Compose.cleanup(function()
						cleanup += 1
					end)
					return ctx.UI.Text {
						text = function(use: Use)
							return tostring(use(value))
						end,
					}
				end)
				local root, content = mounted.root, mounted.content
				value:set(9)
				local nextConfig = config()
				nextConfig.width, nextConfig.height, nextConfig.input = 1280, 800, "Gamepad"
				nextConfig.textSize = "Largest"
				mounted.update(nextConfig)
				Verify.expect((env.viewportWidth:peek())):toBe(1280)
				Verify.expect((env.effectiveInput:peek())):toBe("Gamepad")
				Verify.expect((env.preferredTextSize:peek())):toBe("Largest")
				Verify.expect(content.Text):toBe("9")
				Verify.expect(mounted.root):toBe(root)
				Verify.expect(builds):toBe(1)
				Verify.expect(cleanup):toBe(0)
				mounted.dispose()
				mounted.dispose()
				Verify.expect(cleanup):toBe(1)
				Verify.expect(root.Parent):toBe(nil)
			end,
		})

		verifyHarness:case("gives comparison canvases independent state", {
			id = "facet_designer::Facet Design sessions::gives comparison canvases independent state",
			run = function()
				local cells: { Facet.Cell<number> } = {}
				local function render(ctx)
					local value = ctx.Compose.cell(1)
					table.insert(cells, value)
					return ctx.UI.Text {
						text = function(use: Use)
							return tostring(use(value))
						end,
					}
				end
				local first, second = fixture(render), fixture(render)
				cells[1]:set(5)
				Verify.expect(first.content.Text):toBe("5")
				Verify.expect(second.content.Text):toBe("1")
				first.dispose()
				cells[2]:set(8)
				Verify.expect(second.content.Text):toBe("8")
				second.dispose()
			end,
		})

		verifyHarness:case("releases a partial mount when the preview throws", {
			id = "facet_designer::Facet Design sessions::releases a partial mount when the preview throws",
			run = function()
				local cleanup = 0
				local ok, err = pcall(fixture, function(ctx)
					ctx.Compose.cleanup(function()
						cleanup += 1
					end)
					ctx.UI.Button { label = "Temporary" }
					error("broken sample")
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(err), "broken sample", 1, true) ~= nil):toBe(true)
				Verify.expect(cleanup):toBe(1)
			end,
		})

		verifyHarness:case("keeps presented content inside the canvas overlay", {
			id = "facet_designer::Facet Design sessions::keeps presented content inside the canvas overlay",
			run = function()
				local presented
				local mounted = fixture(function(ctx)
					presented = ctx.Compose.cell(false)
					return ctx.UI.VStack {
						ctx.UI.Button {
							label = "Open",
							onActivate = function()
								presented:set(true)
							end,
						},
						ctx.UI.Dialog {
							title = "Details",
							onPresentedChange = function(value)
								presented:set(value)
							end,
							isPresented = presented,
							content = function(): Instance
								return ctx.UI.Text { text = "Hello" }
							end,
						},
					}
				end)
				presented:set(true)
				local panel = mounted.root:FindFirstChild("Panel", true)
				Verify.expect(panel ~= nil):toBe(true)
				Verify.expect((panel:IsDescendantOf(mounted.overlay))):toBe(true)
				mounted.dispose()
			end,
		})
	end)

	verifyHarness:suite("Facet Design definitions", function()
		verifyHarness:case("rejects duplicate sample names and sparse samples", {
			id = "facet_designer::Facet Design definitions::rejects duplicate sample names and sparse samples",
			run = function()
				local render = function()
					return nil
				end
				local ok = pcall(catalog.validate, {
					name = "Demo",
					previews = { { name = "Empty", render = render }, { name = "Empty", render = render } },
				})
				Verify.expect(ok):toBe(false)
				ok = pcall(catalog.validate, {
					name = "Demo",
					previews = { [1] = { name = "Empty", render = render }, [3] = { name = "Loaded", render = render } },
				})
				Verify.expect(ok):toBe(false)
			end,
		})

		verifyHarness:case("discovers marked modules once even with overlapping roots", {
			id = "facet_designer::Facet Design definitions::discovers marked modules once even with overlapping roots",
			run = function()
				local engine = engines.new()
				local Instance = { new = engine.new }
				local root = Instance.new("Folder")
				local first = Instance.new("ModuleScript")
				first.Name, first.Parent = "Inventory.preview", root
				first.GetFullName = function()
					return "Root.Inventory.preview"
				end
				local second = Instance.new("ModuleScript")
				second.Name, second.Parent = "Account", root
				second.GetFullName = function()
					return "Root.Account"
				end
				second:SetAttribute("FacetDesign", true)
				local ignored = Instance.new("ModuleScript")
				ignored.Name, ignored.Parent = "Model", root
				local found = catalog.discover({ root, root })
				Verify.expect(#found):toBe(2)
				Verify.expect(found[1]):toBe(second)
				Verify.expect(found[2]):toBe(first)
			end,
		})
	end)

	verifyHarness:suite("Facet Design saved libraries", function()
		verifyHarness:case("rejects concurrent session writes without changing stored designs", {
			id = "facet_designer::Facet Design saved libraries::rejects concurrent session writes without changing stored designs",
			run = function()
				local first = savedLibrary.replace(nil, 0, { draft = templates[1], designs = {} })
				local second = savedLibrary.replace(first, 1, { draft = templates[2], designs = {} })
				Verify.expect(second.revision):toBe(2)
				Verify.expect((pcall(savedLibrary.replace, second, 1, { draft = templates[1] }))):toBe(false)
				Verify.expect(second.library.draft.name):toBe(templates[2].name)
			end,
		})
		verifyHarness:case("keeps removed designs through a validated storage reload", {
			id = "facet_designer::Facet Design saved libraries::keeps removed designs through a validated storage reload",
			run = function()
				local stored = savedLibrary.replace(nil, 0, { designs = {}, archived = { Removed = templates[1] } })
				local restored = savedLibrary.validate(stored.library)
				Verify.expect(restored.archived.Removed.name):toBe(templates[1].name)
				restored.designs.Removed = restored.archived.Removed
				restored.archived.Removed = nil
				local nextValue = savedLibrary.replace(stored, 1, restored)
				Verify.expect(nextValue.library.archived.Removed):toBe(nil)
				Verify.expect(nextValue.library.designs.Removed.name):toBe(templates[1].name)
				Verify.expect(stored.library.archived.Removed.name):toBe(templates[1].name)
			end,
		})
		verifyHarness:case("bounds saved designs and keeps untrusted fields out of storage", {
			id = "facet_designer::Facet Design saved libraries::bounds saved designs and keeps untrusted fields out of storage",
			run = function()
				local untrusted = document.copy(templates[1])
				untrusted.extra = untrusted
				untrusted.root.extra = untrusted.root
				local clean = savedLibrary.validate({ draft = untrusted, designs = {}, unrelated = true })
				Verify.expect(clean.unrelated):toBe(nil)
				Verify.expect(clean.draft.extra):toBe(nil)
				Verify.expect(clean.draft.root.extra):toBe(nil)
				clean.draft.name = "Changed copy"
				Verify.expect(templates[1].name == "Changed copy"):toBe(false)
				local tooMany = {}
				for index = 1, 41 do
					tooMany[tostring(index)] = templates[1]
				end
				Verify.expect((pcall(savedLibrary.validate, { designs = tooMany }))):toBe(false)
				Verify.expect((pcall(savedLibrary.validate, { designs = { broken = {} } }))):toBe(false)
			end,
		})
	end)
end
