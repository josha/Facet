--!strict

local t = require("./lib/testkit")
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

t.describe("Facet Design documents and source", function()
	t.it("has an adapter for every public control constructor", function()
		local fs = require("@lune/fs")
		local sourceTypes = fs.readFile("src/ui/control_types.luau")
		local count = 0
		for name in string.gmatch(sourceTypes, "\n\t([A-Z][%w]+):") do
			count += 1
			t.expect(library.definitions[name] ~= nil).toBe(true)
		end
		t.expect(#library.names()).toBe(count)
	end)
	t.it("duplicates subtrees with unique IDs and rejects moves into descendants", function()
		local value = document.copy(templates[1])
		local copied, id = document.duplicate(value, "n5")
		t.expect(#document.rows(copied.root)).toBe(13)
		t.expect(id).toBe("n10")
		t.expect(#document.rows(value.root)).toBe(9)
		t.expect(function()
			document.move(copied, "n10", "n11")
		end).toThrow()
		t.expect(function()
			document.remove(value, "n1")
		end).toThrow()
	end)
	t.it("reorders outline slots without losing subtrees or renames in undo", function()
		local value = document.copy(templates[1])
		local moved = document.reorder(value, "n2", 3)
		t.expect(moved.root.children[3].id).toBe("n2")
		t.expect(document.reorder(moved, "n2", 1).root.children[1].id).toBe("n2")
		local subtree = document.reorder(value, "n5", 8)
		t.expect(subtree.root.children[#subtree.root.children].id).toBe("n5")
		t.expect(#document.find(subtree.root, "n5").children).toBe(3)
		t.expect(document.reorder(value, "n5", 4)).toBe(value)
		local nested = document.reorder(value, "n2", 5)
		t.expect(select(2, document.find(nested.root, "n2")).id).toBe("n5")
		t.expect(function()
			document.reorder(value, "n1", 1)
		end).toThrow()
		local stack = history.new(value)
		stack.commit(document.change(value, "n3", "name", "Trail heading"), "n3")
		t.expect(document.find(stack.current().root, "n3").name).toBe("Trail heading")
		stack.undo()
		t.expect(document.find(stack.current().root, "n3").name).toBe("Heading")
	end)

	t.it("restores selection with undo and invalidates redo after a new edit", function()
		local stack = history.new(document.new())
		local first, id = document.insert(stack.current(), "n1", "Text")
		stack.commit(first, id)
		stack.commit(document.change(first, id, "text", "Second"), id)
		stack.undo()
		local reverted, selected = stack.current()
		t.expect(selected).toBe(id)
		t.expect(document.find(reverted.root, id).props.text).toBe("A little possibility")
		stack.undo()
		t.expect(select(2, stack.current())).toBe("n1")
		stack.redo()
		stack.commit(document.change(stack.current(), id, "text", "Branch"), id)
		t.expect(stack.canRedo()).toBe(false)
	end)
	t.it("resets an edited property to its adapter default without losing undo", function()
		local value, id = document.insert(document.new(), "n1", "Text")
		local stack = history.new(value)
		stack.select(id)
		stack.commit(document.change(value, id, "text", "Edited title"), id)
		stack.commit(document.change(stack.current(), id, "text", nil), id)
		local reset = stack.current()
		t.expect(document.find(reset.root, id).props.text).toBe(nil)
		t.expect(string.find(exporter.component(reset), 'text = "A little possibility"', 1, true) ~= nil).toBe(true)
		stack.undo()
		t.expect(document.find(stack.current().root, id).props.text).toBe("Edited title")
		stack.redo()
		t.expect(document.find(stack.current().root, id).props.text).toBe(nil)
	end)

	t.it("renders every inspector preset and keeps its export stable", function()
		local failures = {}
		for _, kind in library.names() do
			local value, id
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
							t.expect(exporter.component(source.parse(code, edited.name))).toBe(code)
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
	end)

	t.it("round trips every template through editable Luau", function()
		for _, value in templates do
			local code = exporter.component(value)
			local parsed = source.parse(code, value.name)
			t.expect(exporter.component(parsed)).toBe(code)
		end
	end)
	t.it("keeps literal code-looking text and rejects executable property expressions", function()
		local value, id = document.insert(document.new(), "n1", "Text")
		value = document.change(value, id, "text", '"\n\\ UI.Button { label = "Injected" }\t🌲')
		local code = exporter.component(value)
		t.expect(exporter.component(source.parse(code, value.name))).toBe(code)
		t.expect(function()
			source.parse(string.gsub(code, 'textRole = "body"', "textRole = getRole()"), value.name)
		end).toThrow()
	end)
	t.it("rejects cyclic documents, sparse children, unknown properties, and invalid choices", function()
		local value = document.new()
		value.root.children[1] = value.root
		t.expect(function()
			document.validate(value)
		end).toThrow()
		value = document.new()
		value.root.children[2] = { id = "n2", kind = "Text", name = "Text", props = {}, children = {} }
		t.expect(function()
			document.validate(value)
		end).toThrow()
		value = document.new()
		value.root.props.bad = true
		t.expect(function()
			document.validate(value)
		end).toThrow()
		t.expect(function()
			library.parse(library.descriptor("Button", "appearance"), "unknown")
		end).toThrow()
	end)
	for _, kind in library.names() do
		t.it("exports and mounts " .. kind .. " using the current Facet API", function()
			local value = document.new()
			if kind ~= "Screen" then
				value = document.insert(value, "n1", kind)
			end
			local code = exporter.component(value)
			t.expect(exporter.component(source.parse(code, value.name))).toBe(code)
			local mounted = fixture(function(ctx)
				return render.build(value, ctx)
			end)
			t.expect(mounted.content.Name).toBe("Screen")
			mounted.dispose()
		end)
	end
end)

t.describe("Facet Design browsing and transfer", function()
	t.it("filters both titles and categories and bounds visual pages", function()
		local entries = {}
		for index = 1, 15 do
			table.insert(entries, {
				id = tostring(index),
				label = "Design " .. index,
				detail = if index % 2 == 0 then "Input" else "Layout",
			})
		end
		local page, pages = gallery.page(entries, "INPUT", 1)
		t.expect(#page).toBe(6)
		t.expect(pages).toBe(2)
		page = gallery.page(entries, "input", 10)
		t.expect(#page).toBe(1)
		t.expect(page[1].id).toBe("14")
		t.expect(#gallery.page(entries, "no matches", 1)).toBe(0)
	end)
	t.it("transfers editable designs without executable or unknown metadata", function()
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
			t.expect(imported.metadata).toBe(nil)
			t.expect(exporter.component(imported)).toBe(exporter.component(template))
		end
		t.expect(function()
			transfer.decode('{"format":"facet-design-file/2"}', decode)
		end).toThrow()
		t.expect(function()
			transfer.decode('{"format":"facet-design-file/1"}', decode)
		end).toThrow()
		t.expect(function()
			transfer.decode(string.rep("x", 900001), decode)
		end).toThrow()
		t.expect(function()
			transfer.decode('{"format":"facet-design-file/1","design":{}}', decode)
		end).toThrow()
	end)
	t.it("round trips side padding and explicit colors through code", function()
		local value =
			document.change(document.new(), "n1", "padding", { top = "m", right = 24, bottom = 8, left = "s" })
		value = document.change(value, "n1", "BackgroundColor3", "#143357")
		local code = exporter.component(value)
		t.expect(exporter.component(source.parse(code, value.name))).toBe(code)
		local mounted = fixture(function(ctx)
			return render.build(value, ctx)
		end)
		mounted.dispose()
		t.expect(function()
			document.change(value, "n1", "padding", { center = 2 })
		end).toThrow()
		t.expect(function()
			document.change(value, "n1", "BackgroundTransparency", 2)
		end).toThrow()
	end)
	t.it("preserves document bounds and branch history over a long editing session", function()
		local value, id = document.insert(document.new(), "n1", "Text")
		local stack = history.new(value)
		for index = 1, 150 do
			stack.commit(document.change(stack.current(), id, "text", "Revision " .. index), id)
			if index % 5 == 0 then
				stack.undo()
				stack.redo()
			end
		end
		t.expect(document.find(stack.current().root, id).props.text).toBe("Revision 150")
		stack.undo()
		t.expect(document.find(stack.current().root, id).props.text).toBe("Revision 149")
		stack.commit(document.change(stack.current(), id, "text", "New branch"), id)
		t.expect(stack.canRedo()).toBe(false)
	end)
end)

t.describe("Facet Design agent edits", function()
	t.it("applies an atomic batch by layer name and keeps code visually editable", function()
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
		t.expect(exporter.component(source.parse(generated, value.name))).toBe(generated)
		t.expect(string.find(generated, "An agent designed this", 1, true) ~= nil).toBe(true)
		t.expect(exporter.component(templates[1])).toBe(code)
		local mounted = fixture(function(ctx)
			return render.build(value, ctx)
		end)
		mounted.dispose()
	end)
	t.it("rejects invalid batches and custom source before changing anything", function()
		local value = document.copy(templates[1])
		t.expect(function()
			agent.apply(value, {
				{ op = "set", node = "Heading", property = "text", value = "Temporary" },
				{ op = "set", node = "Heading", property = "unknown", value = true },
			})
		end).toThrow()
		t.expect(document.find(value.root, "n3").props.text).toBe(templates[1].root.children[2].props.text)
		local code = exporter.component(value)
		t.expect(function()
			agent.patch(code .. "\ncustomGameLogic()", { { op = "remove", node = "Heading" } })
		end).toThrow()
	end)
end)

t.describe("Facet Design sessions", function()
	t.it("updates device facts without remounting local state or native content", function()
		local builds, cleanup = 0, 0
		local value, env
		local mounted = fixture(function(ctx)
			builds += 1
			value = ctx.Compose.cell(7)
			env = ctx.UI.environment()
			ctx.Compose.cleanup(function()
				cleanup += 1
			end)
			return ctx.UI.Text {
				text = function(use)
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
		t.expect(env.viewportWidth:peek()).toBe(1280)
		t.expect(env.effectiveInput:peek()).toBe("Gamepad")
		t.expect(env.preferredTextSize:peek()).toBe("Largest")
		t.expect(content.Text).toBe("9")
		t.expect(mounted.root).toBe(root)
		t.expect(builds).toBe(1)
		t.expect(cleanup).toBe(0)
		mounted.dispose()
		mounted.dispose()
		t.expect(cleanup).toBe(1)
		t.expect(root.Parent).toBe(nil)
	end)

	t.it("gives comparison canvases independent state", function()
		local cells = {}
		local function render(ctx)
			local value = ctx.Compose.cell(1)
			table.insert(cells, value)
			return ctx.UI.Text {
				text = function(use)
					return tostring(use(value))
				end,
			}
		end
		local first, second = fixture(render), fixture(render)
		cells[1]:set(5)
		t.expect(first.content.Text).toBe("5")
		t.expect(second.content.Text).toBe("1")
		first.dispose()
		cells[2]:set(8)
		t.expect(second.content.Text).toBe("8")
		second.dispose()
	end)

	t.it("releases a partial mount when the preview throws", function()
		local cleanup = 0
		local ok, err = pcall(fixture, function(ctx)
			ctx.Compose.cleanup(function()
				cleanup += 1
			end)
			ctx.UI.Button { label = "Temporary" }
			error("broken sample")
		end)
		t.expect(ok).toBe(false)
		t.expect(string.find(tostring(err), "broken sample", 1, true) ~= nil).toBe(true)
		t.expect(cleanup).toBe(1)
	end)

	t.it("keeps presented content inside the canvas overlay", function()
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
					content = function()
						return ctx.UI.Text { text = "Hello" }
					end,
				},
			}
		end)
		presented:set(true)
		local panel = mounted.root:FindFirstChild("Panel", true)
		t.expect(panel ~= nil).toBe(true)
		t.expect(panel:IsDescendantOf(mounted.overlay)).toBe(true)
		mounted.dispose()
	end)
end)

t.describe("Facet Design definitions", function()
	t.it("rejects duplicate sample names and sparse samples", function()
		local render = function()
			return nil
		end
		local ok = pcall(
			catalog.validate,
			{ name = "Demo", previews = { { name = "Empty", render = render }, { name = "Empty", render = render } } }
		)
		t.expect(ok).toBe(false)
		ok = pcall(catalog.validate, {
			name = "Demo",
			previews = { [1] = { name = "Empty", render = render }, [3] = { name = "Loaded", render = render } },
		})
		t.expect(ok).toBe(false)
	end)

	t.it("discovers marked modules once even with overlapping roots", function()
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
		t.expect(#found).toBe(2)
		t.expect(found[1]).toBe(second)
		t.expect(found[2]).toBe(first)
	end)
end)

t.describe("Facet Design saved libraries", function()
	t.it("rejects concurrent session writes without changing stored designs", function()
		local first = savedLibrary.replace(nil, 0, { draft = templates[1], designs = {} })
		local second = savedLibrary.replace(first, 1, { draft = templates[2], designs = {} })
		t.expect(second.revision).toBe(2)
		t.expect(pcall(savedLibrary.replace, second, 1, { draft = templates[1] })).toBe(false)
		t.expect(second.library.draft.name).toBe(templates[2].name)
	end)
	t.it("keeps removed designs through a validated storage reload", function()
		local stored = savedLibrary.replace(nil, 0, { designs = {}, archived = { Removed = templates[1] } })
		local restored = savedLibrary.validate(stored.library)
		t.expect(restored.archived.Removed.name).toBe(templates[1].name)
		restored.designs.Removed = restored.archived.Removed
		restored.archived.Removed = nil
		local nextValue = savedLibrary.replace(stored, 1, restored)
		t.expect(nextValue.library.archived.Removed).toBe(nil)
		t.expect(nextValue.library.designs.Removed.name).toBe(templates[1].name)
		t.expect(stored.library.archived.Removed.name).toBe(templates[1].name)
	end)
	t.it("bounds saved designs and keeps untrusted fields out of storage", function()
		local untrusted = document.copy(templates[1])
		untrusted.extra = untrusted
		untrusted.root.extra = untrusted.root
		local clean = savedLibrary.validate({ draft = untrusted, designs = {}, unrelated = true })
		t.expect(clean.unrelated).toBe(nil)
		t.expect(clean.draft.extra).toBe(nil)
		t.expect(clean.draft.root.extra).toBe(nil)
		clean.draft.name = "Changed copy"
		t.expect(templates[1].name == "Changed copy").toBe(false)
		local tooMany = {}
		for index = 1, 41 do
			tooMany[tostring(index)] = templates[1]
		end
		t.expect(pcall(savedLibrary.validate, { designs = tooMany })).toBe(false)
		t.expect(pcall(savedLibrary.validate, { designs = { broken = {} } })).toBe(false)
	end)
end)
