--!strict
local Verify = require("../tools/vendor/verify/src/core")
local Facet = require("../src")
local world = require("./lib/overlay_world")
local Vector2 = require("./lib/native_engine").types.Vector2

return function(harness: Verify.Harness)
	local fs = require("@std/fs")
	local Lute = require("../tools/vendor/verify/src/lute")
	local Compose = Facet.Compose
	local source = fs.readFileToString("examples/blocks/navigable_dialog_design.luau")
	type Props = {
		open: Facet.Value<boolean>,
		path: Facet.Value<Facet.NavigationPath>,
		music: Facet.Value<boolean>,
		volume: Facet.Value<number>,
		onDetails: (() -> ())?,
		onPresentedChange: ((boolean) -> ())?,
	}
	type Component = (Facet.Controls, Props) -> GuiObject
	local build = Lute.chunk.load(source, {
		name = "navigable_dialog_design",
		environment = {
			game = {
				GetService = function()
					return { Facet = "Facet" }
				end,
			},
			require = function()
				return Facet
			end,
		},
	})() :: Component
	local function model(): Props
		local open = Compose.cell(true)
		local path = Compose.cell<<Facet.NavigationPath>>({})
		return {
			open = open,
			path = path,
			music = Compose.cell(true),
			volume = Compose.cell(50),
			onPresentedChange = function(value: boolean)
				open:set(value)
			end,
			onDetails = function()
				path:set({ { id = "details" } })
			end,
		}
	end

	harness:case("the canonical Design offers a bounded body at each display size", {
		id = "dialog-bounds-device-matrix",
		run = function(t: Verify.Context)
			local base = Facet.themes.neutralPackage()
			for _, size in { { 390, 844 }, { 844, 390 }, { 1024, 768 }, { 1920, 1080 }, { 3840, 2160 } } do
				local props = model()
				local package = Facet.themes.forResolution(base, size[1], size[2])
				local w = world.new(function(UI)
					return build(UI, props)
				end, { theme = package, motionLevel = "none" }, { size = Vector2.new(size[1], size[2]) })
				t:defer(w.stop)
				local scale = Facet.adaptive.resolutionScale(size[1], size[2])
				w.size(w.find("Header"), 300 * scale, 44 * scale)
				local body, panel = w.find("Body"), w.find("Panel")
				local expected = math.min(420 * scale, size[2] - 32 - 2 * package.metrics.space.m - 44 * scale - 8)
				t:expect(body.Size.Y.Offset):toBe(expected)
				t:expect(body.CanvasSize.Y.Offset):toBe(expected)
				t:expect(body.Selectable):toBe(false)
				t:expect(panel.Size.X.Offset < size[1]):toBe(true)
				t:expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
				t:expect(w.find("PreferencesNavigation").Size.Y.Scale):toBe(1)
				t:expect(w.find("PreferencesForm").Size.Y.Scale):toBe(1)
				t:expect(w.find("Measure")):toBe(nil)
			end
		end,
	})

	harness:case("bounded fill follows the offered room and keeps its navigation state on resize", {
		id = "dialog-bounds-fill-resize",
		run = function(t: Verify.Context)
			local shown = Compose.cell(true)
			local height = Compose.cell<<Facet.DialogBodyHeight>>("fill")
			local policy = Compose.cell<<Facet.DialogPresentation>>("inset")
			local w = world.new(function(UI)
				return UI.Dialog {
					isPresented = shown,
					closeButton = false,
					presentation = policy,
					bodyHeight = height,
					content = function()
						return UI.NavigationStack {
							path = Compose.cell({}),
							root = {
								content = function()
									return UI.ScrollView { height = "fill", width = "fill" }
								end,
							},
							destinations = {},
						}
					end,
				}
			end, { motionLevel = "none" }, { size = Vector2.new(844, 390) })
			t:defer(w.stop)
			local body = w.find("Body")
			local content = world.find(body, "Content")
			t:expect(body.Size.Y.Offset):toBe(326)
			t:expect(content.AutomaticSize):toBe(w.Enum.AutomaticSize.None)
			t:expect(content.Size.Y.Scale):toBe(1)
			w.size(w.screen, 390, 844)
			t:expect(body.Size.Y.Offset):toBe(780)
			t:expect(w.find("Body")):toBe(body)
			height:set(240)
			t:expect(body.Size.Y.Offset):toBe(240)
			w.engine.environment.poke(w.input, "OnScreenKeyboardSize", Vector2.new(390, 400))
			w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", true)
			height:set("fill")
			t:expect(body.Size.Y.Offset):toBe(380)
			t:expect(w.find("Panel").Position.Y.Offset):toBe(-200)
			w.engine.environment.poke(w.input, "OnScreenKeyboardVisible", false)
			height:set(240)
			policy:set("automatic")
			t:expect(w.find("Panel").AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
			w.size(w.screen, 844, 180)
			t:expect(w.find("Panel").Size.Y.Offset):toBe(180)
			policy:set("inset")
			t:expect(body.Size.Y.Offset):toBe(116)
			t:expect(w.find("Panel").AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
		end,
	})

	harness:case("logical body height follows reactive resolution and ten-foot scaling once", {
		id = "dialog-bounds-logical-scale",
		run = function(t: Verify.Context)
			local base = Facet.themes.neutralPackage()
			local package = Compose.cell<<Facet.ReadOnlyThemePackage>>(base)
			local w = world.new(
				function(UI)
					return build(UI, model())
				end,
				{ theme = package, environment = { viewingDistance = "ten-foot" }, motionLevel = "none" },
				{ size = Vector2.new(1920, 1080) }
			)
			t:defer(w.stop)
			t:expect(w.find("Body").Size.Y.Offset):toBe(630)
			local width = w.find("Panel").Size.X.Offset
			package:set(Facet.themes.forResolution(base, 3840, 2160))
			w.size(w.screen, 3840, 2160)
			t:expect(w.find("Body").Size.Y.Offset):toBe(1260)
			t:expect(w.find("Panel").Size.X.Offset):toBe(width * 2)
			package:set(base)
			w.size(w.screen, 1920, 1080)
			t:expect(w.find("Body").Size.Y.Offset):toBe(630)
		end,
	})

	harness:case("inset natural content scrolls within theme insets and unpins in a tiny room", {
		id = "dialog-bounds-natural-overflow",
		run = function(t: Verify.Context)
			local package = Facet.themes.neutralPackage()
			package.chrome = { panel = { kind = "native", contentInsets = { top = 24, bottom = 40 } } }
			local w = world.new(function(UI)
				return UI.Dialog {
					isPresented = Compose.cell(true),
					closeButton = false,
					title = "Preferences",
					presentation = "inset",
					content = function()
						return UI.Text { text = "Long content", wrap = true }
					end,
				}
			end, { theme = package, motionLevel = "none" }, { size = Vector2.new(844, 390) })
			t:defer(w.stop)
			local body, room, panel = w.find("Body"), w.find("Room"), w.find("Panel")
			w.size(w.find("Header"), 300, 44)
			w.size(world.find(body, "Content"), 300, 800)
			t:expect(body.Size.Y.Offset):toBe(242)
			t:expect(body.CanvasSize.Y.Offset):toBe(800)
			t:expect(body.Selectable):toBe(true)
			t:expect(room.ScrollingEnabled):toBe(false)
			t:expect(panel.Size.X.Offset < 844):toBe(true)
			t:expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
			w.size(w.screen, 844, 160)
			t:expect(room.ScrollingEnabled):toBe(true)
			t:expect(room.Size.Y.Offset):toBe(64)
			t:expect(body.ScrollingEnabled):toBe(false)
			t:expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
		end,
	})

	harness:case("the canonical Design preserves Back dismissal focus and host ownership", {
		id = "dialog-bounds-navigation-focus-dismissal",
		run = function(t: Verify.Context)
			local props = model()
			props.open:set(false)
			local w = world.new(function(UI, Host, _, gui)
				local opener = UI.Button "OpenPreferences" {
					label = "Preferences",
					onActivate = function()
						props.open:set(true)
					end,
				}
				gui.SelectedObject = opener
				return Host.Frame { opener, build(UI, props) }
			end, { motionLevel = "none" }, { size = Vector2.new(844, 390) })
			t:defer(w.stop)
			w.find("OpenPreferences").Activated:Fire()
			local body = w.find("Body")
			t:expect(w.find("Back")):toBe(nil)
			w.find("Details").Activated:Fire()
			t:expect(#props.path:peek()):toBe(1)
			t:expect(w.find("Back") ~= nil):toBe(true)
			w.find("Back").Activated:Fire()
			t:expect(#props.path:peek()):toBe(0)
			t:expect(props.open:peek()):toBe(true)
			t:expect(w.find("Body")):toBe(body)
			w.find("Close").Activated:Fire()
			t:expect(props.open:peek()):toBe(false)
			t:expect(w.gui.SelectedObject):toBe(w.find("OpenPreferences"))
			props.open:set(true)
			t:expect(w.find("Body")):toBe(body)
			t:expect(#w.findAll("PreferencesNavigation")):toBe(1)
			for _, node in w.screen:GetDescendants() do
				t:expect(node:IsA("ScreenGui")):toBe(false)
			end
		end,
	})

	harness:case("Design retains both numeric and fill body offers through edits and rendering", {
		id = "dialog-bounds-design-roundtrip",
		run = function(t: Verify.Context)
			local kit = Facet.design()
			local w = world.new(function(UI, _, engine)
				local library = kit.library({ UI = UI, types = engine.types })
				local value = kit.Design.parse(source, library)
				t:expect(kit.Design.emit(value, library, { name = value.name })):toBe(source)
				t:expect(library.kinds.Dialog.fields.bodyHeight.also):toEqual({ "number" })
				value = kit.Design.document.change(value, library, value.root.id, "bodyHeight", { literal = "fill" })
				local emitted = kit.Design.emit(value, library)
				t:expect(kit.Design.emit(kit.Design.parse(emitted, library), library)):toBe(emitted)
				local rendered = kit.Design.render(value, library)
				assert(typeof(rendered) == "Instance")
				return rendered
			end, { motionLevel = "none" }, { size = Vector2.new(844, 390) })
			t:defer(w.stop)
			t:expect(w.find("Body").Size.Y.Offset > 0):toBe(true)
			t:expect(w.find("Panel").Size.X.Offset < 844):toBe(true)
		end,
	})
end
