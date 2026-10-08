--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type Readable<T> = { peek: (Readable<T>) -> T }
	type Use = <T>(Readable<T>) -> T

	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local session = require("../tools/designer/modules/session")
	local document = require("../tools/designer/modules/document")
	local history = require("../tools/designer/modules/history")
	local library = require("../tools/designer/modules/library")
	local templates = require("../tools/designer/modules/templates")
	local exporter = require("../tools/designer/modules/export")
	local source = require("../tools/designer/modules/source")
	local agent = require("../tools/designer/modules/agent")
	local transfer = require("../tools/designer/modules/transfer")
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

	verifyHarness:suite("Facet Design editor overlays", function()
		verifyHarness:case("covers native insets and moves selection into the active custom panel", {
			id = "facet_designer::Facet Design editor overlays::covers native insets and moves selection into the active custom panel",
			run = function()
				local overlay = require("../tools/designer/modules/editor_overlay")
				local engine: any = engines.new()
				local gui, input = engine.new("GuiService"), engine.new("UserInputService")
				local E, V2, D2 = engine.types.Enum, engine.types.Vector2, engine.types.UDim2
				local near, far = V2.new(0, 58), V2.new(0, 0)
				gui.GetGuiInset = function()
					return near, far
				end
				input.PreferredInput = E.PreferredInput.KeyboardAndMouse
				local runtime = Facet.Roblox.createRuntime(engine)
				local Host: any = runtime.constructors
				local parent = engine.new("ScreenGui")
				parent.ScreenInsets = E.ScreenInsets.CoreUISafeInsets
				local model =
					Facet.Compose.cell({ menuTitle = "", dataTitle = "", transferTitle = "", galleryTitle = "" })
				local trigger, menu, transferPanel, scrim
				local stop = runtime.mount(function()
					local UI = Facet.controls(
						runtime,
						{ types = engine.types, services = { GuiService = gui, UserInputService = input } }
					)
					trigger = Host.TextButton "Trigger" { Selectable = true }
					menu = Host.Frame "Menu" {
						Visible = function(use: Use)
							return use(model).menuTitle ~= ""
						end,
						Host.TextButton "CloseMenu" { Selectable = true },
					}
					transferPanel = Host.Frame "Transfer" {
						Visible = function(use: Use)
							return use(model).transferTitle ~= ""
						end,
						Host.TextButton "CloseTransfer" { Selectable = true },
					}
					local bound = overlay.bind(
						Facet,
						runtime,
						UI,
						Host,
						parent,
						{ menu = menu, transfer = transferPanel },
						model,
						{ types = engine.types, guiService = gui }
					)
					scrim = bound.scrim
					return Host.Frame { trigger, menu, transferPanel, scrim, bound.focus }
				end, parent)
				Verify.expect(scrim.Position):toBe(D2.fromOffset(0, -58))
				Verify.expect(scrim.Size):toBe(D2.new(1, 0, 1, 58))
				near = V2.new(8, 64)
				far = V2.new(4, 3)
				gui.TopbarInset = engine.types.Rect.new(0, 0, 10, 64)
				Verify.expect(scrim.Position):toBe(D2.fromOffset(-8, -64))
				Verify.expect(scrim.Size):toBe(D2.new(1, 12, 1, 67))
				gui.SelectedObject = trigger
				model:set({ menuTitle = "Files", dataTitle = "", transferTitle = "", galleryTitle = "" })
				Verify.expect(gui.SelectedObject:IsDescendantOf(menu)):toBe(true)
				model:set({ menuTitle = "", dataTitle = "", transferTitle = "Import", galleryTitle = "" })
				Verify.expect(gui.SelectedObject:IsDescendantOf(transferPanel)):toBe(true)
				model:set({ menuTitle = "", dataTitle = "", transferTitle = "", galleryTitle = "" })
				Verify.expect(gui.SelectedObject):toBe(trigger)
				stop()
				runtime:dispose()
			end,
		})
	end)

	verifyHarness:suite("Facet Design documents and source", function()
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

		for _, kind in library.names() do
		end
	end)

	verifyHarness:suite("Facet Design browsing and transfer", function()
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
	end)
end
