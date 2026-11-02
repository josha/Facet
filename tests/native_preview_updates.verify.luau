--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	local FixtureOverlayTypes = require("../src/ui/overlay_types")
	local SharedTypes = require("../src/ui/types")
	type ExampleContext = typeof(require("@repo/examples/types").Context)

	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local gallery = require("../examples/gallery/client/screen")
	local labSettings = require("../examples/facet-lab/src/lab_settings")
	local C = Facet.Compose

	local function fixture(build: (Facet.Controls, Facet.Host, SharedTypes.RobloxTypes) -> Facet.Child)
		local engine = engines.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		engine.environment.poke(input, "PreferredInput", engine.types.Enum.PreferredInput.KeyboardAndMouse)
		input.GetFocusedTextBox = function()
			return nil
		end
		local ctx: any = {
			Compose = C,
			Facet = Facet,
			runtime = runtime,
			Host = Facet.host(runtime),
			types = engine.types,
			guiService = gui,
			viewport = C.cell({ width = 1440, height = 900 }),
		}
		local made: labSettings.Settings? = nil
		local controls: Facet.Controls? = nil
		local stop, root: any = runtime.mount(function()
			local scope: ExampleContext = ctx
			gallery.configure(scope)
			local settings = labSettings.new(ctx, input)
			made = settings
			local overlay: Instance = ctx.overlayParent
			local UI = Facet.controls(runtime, {
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				environment = settings.environment,
				overlayParent = overlay,
				motionLevel = "none",
			})
			controls = UI
			local Host = Facet.host(runtime)
			return Host.ScreenGui { overlay, build(UI, Host, engine.types) }
		end, engine.new("Folder"))
		engine.environment.poke(root, "AbsoluteSize", engine.types.Vector2.new(1440, 900))
		engine.environment.poke(ctx.overlayParent, "AbsoluteSize", engine.types.Vector2.new(389, 762))
		engine.environment.poke(ctx.overlayParent, "AbsolutePosition", engine.types.Vector2.new(400, 50))
		return {
			engine = engine,
			ctx = ctx,
			settings = assert(made),
			root = root,
			UI = assert(controls),
			input = input,
			find = function(name)
				return root:FindFirstChild(name, true)
			end,
			stop = function()
				stop()
				runtime:dispose()
			end,
		}
	end

	verifyHarness:suite("settings update mounted controls and their presentation bounds", function()
		for _, kind in { "color", "date" } :: { "color" | "date" } do
			verifyHarness:case(
				kind .. " picker adapts in place to touch, console and pointer inside the preview bounds",
				{
					id = "native_preview_updates::"
						.. "settings update mounted controls and their presentation bounds"
						.. "::"
						.. kind
						.. " picker adapts in place to touch, console and pointer inside the preview bounds",
					run = function()
						local opened = C.cell(false)
						local day: Facet.CivilDate? = { year = 2026, month = 9, day = 30 }
						local w = fixture(function(UI, _, T)
							return if kind == "color"
								then UI.ColorPicker "Picker" {
									value = C.cell(T.Color3.new(1, 0, 0)),
									isPresented = opened,
								}
								else UI.DateTimePicker "Picker" {
									value = C.cell(day),
									onChange = function() end,
									isPresented = opened,
								}
						end)
						w.settings.set("platform", "phone")
						opened:set(true)
						local root = w.find("Picker")
						local panelName = if kind == "color" then "Panel" else "CalendarSurface"
						local panel = w.find(panelName)
						local key = if kind == "color" then "placement" else "route"
						Verify.expect((root:GetAttribute(key))):toBe("sheet")
						Verify.expect((panel:IsDescendantOf(w.ctx.overlayParent))):toBe(true)
						if kind == "color" then
							Verify.expect(panel.Size.X.Offset):toBe(365)
							Verify.expect(w.find("Readout").LayoutOrder):toBe(2)
						end
						w.settings.set("input", "pointer")
						if kind == "date" then
							Verify.expect(root:GetAttribute(key)):toBe("sheet")
						else
							Verify.expect(root:GetAttribute(key) ~= "sheet"):toBe(true)
						end
						if kind == "color" then
							Verify.expect(w.find("Readout").LayoutOrder):toBe(5)
						end
						w.settings.set("input", "automatic")
						Verify.expect((root:GetAttribute(key))):toBe("sheet")
						w.settings.set("platform", "tv")
						Verify.expect((root:GetAttribute(key))):toBe(if kind == "color" then "center" else "sheet")
						Verify.expect((w.find(panelName))):toBe(panel)
						Verify.expect((opened:peek())):toBe(true)
						w.settings.set("platform", "phone")
						local T = w.ctx.types
						local anchor = w.find(if kind == "color" then "Well" else "Field")
						w.engine.environment.poke(anchor, "AbsolutePosition", T.Vector2.new(430, 800))
						w.engine.environment.poke(anchor, "AbsoluteSize", T.Vector2.new(300, 44))
						if kind == "color" then
							w.engine.environment.poke(w.find("ShowSpectrum"), "AbsoluteSize", T.Vector2.new(340, 500))
						else
							w.engine.environment.poke(w.find("Calendar"), "AbsoluteSize", T.Vector2.new(340, 500))
						end
						w.engine.environment.poke(w.ctx.overlayParent, "AbsoluteSize", T.Vector2.new(844, 390))
						w.engine.environment.poke(
							panel,
							"AbsoluteSize",
							T.Vector2.new(panel.Size.X.Offset, panel.Size.Y.Offset)
						)
						Verify.expect(panel.Position.Y.Offset >= 0):toBe(true)
						Verify.expect(panel.Position.Y.Offset + panel.Size.Y.Offset <= 390):toBe(true)
						Verify.expect((w.find(panelName))):toBe(panel)
						w.stop()
					end,
				}
			)
		end

		verifyHarness:case("dialog width follows a resized overlay parent rather than the desktop window", {
			id = "native_preview_updates::settings update mounted controls and their presentation bounds::dialog width follows a resized overlay parent rather than the desktop window",
			run = function()
				local opened = C.cell(false)
				local w = fixture(function(UI)
					return UI.Dialog {
						isPresented = opened,
						title = "Preview",
						content = function(): Instance
							return UI.Text { text = "Keep this inside the preview." }
						end,
						actions = {
							{ id = "close", label = "Close", onActivate = function() end } :: FixtureOverlayTypes.DialogAction,
						},
					}
				end)
				opened:set(true)
				local panel = w.find("Panel")
				Verify.expect((panel:IsDescendantOf(w.ctx.overlayParent))):toBe(true)
				Verify.expect(panel.Size.X.Offset <= 389):toBe(true)
				w.engine.environment.poke(w.ctx.overlayParent, "AbsoluteSize", w.ctx.types.Vector2.new(300, 500))
				Verify.expect(panel.Size.X.Offset <= 300):toBe(true)
				Verify.expect((w.find("Panel"))):toBe(panel)
				w.stop()
			end,
		})
	end)
	return nil
end
