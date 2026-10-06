--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	local FixtureOverlayTypes = require("../src/ui/overlay_types")

	local Facet = require("../src")
	local engines = require("./lib/native_engine")
	local gallery = require("../examples/gallery/client/screen")
	local labSettings = require("../examples/facet-lab/src/lab_settings")
	local C = Facet.Compose

	local function fixture(build)
		local engine = engines.new()
		local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
		local gui, input = engine.new("GuiService"), engine.new("UserInputService")
		input.PreferredInput = engine.types.Enum.PreferredInput.KeyboardAndMouse
		input.GetFocusedTextBox = function()
			return nil
		end
		local ctx = {
			Compose = C,
			Facet = Facet,
			runtime = runtime,
			Host = (runtime.constructors :: unknown) :: RobloxHost,
			types = engine.types,
			guiService = gui,
			viewport = C.cell({ width = 1440, height = 900 }),
		}
		local settings, UI
		local stop, root: any = runtime.mount(function()
			gallery.configure(ctx)
			settings = labSettings.new(ctx, input)
			UI = Facet.controls(runtime, {
				types = engine.types,
				services = { GuiService = gui, UserInputService = input },
				environment = settings.environment,
				overlayParent = ctx.overlayParent,
				motionLevel = "none",
			})
			return ctx.Host.ScreenGui { ctx.overlayParent :: unknown, build(UI, ctx.Host, engine.types) }
		end, engine.new("Folder"))
		root.AbsoluteSize = engine.types.Vector2.new(1440, 900)
		ctx.overlayParent.AbsoluteSize = engine.types.Vector2.new(389, 762)
		ctx.overlayParent.AbsolutePosition = engine.types.Vector2.new(400, 50)
		return {
			ctx = ctx,
			settings = settings,
			root = root,
			UI = UI,
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
		verifyHarness:case(
			"automatic lab input follows the device, explicit input wins, and reset restores native facts",
			{
				id = "native_preview_updates::settings update mounted controls and their presentation bounds::automatic lab input follows the device, explicit input wins, and reset restores native facts",
				run = function()
					local w = fixture(function(UI: FacetControls)
						return UI.Text { text = "Preview" }
					end)
					local env
					local stop = w.ctx.runtime.mount(function()
						env = w.UI.environment()
						return w.ctx.Host.Folder {}
					end, w.root)
					for _, pair in
						{
							{ "phone", "Touch" },
							{ "tablet", "Touch" },
							{ "tv", "Gamepad" },
							{ "desktop", "KeyboardAndMouse" },
						}
					do
						w.settings.set("platform", pair[1])
						Verify.expect((env.effectiveInput:peek())):toBe(pair[2])
					end
					w.settings.set("input", "pointer")
					w.settings.set("platform", "phone")
					Verify.expect((env.effectiveInput:peek())):toBe("KeyboardAndMouse")
					w.settings.set("input", "automatic")
					Verify.expect((env.effectiveInput:peek())):toBe("Touch")
					Verify.expect((w.settings.hover:peek())):toBe(false)
					w.settings.reset()
					Verify.expect((env.effectiveInput:peek())):toBe("KeyboardAndMouse")
					stop()
					w.stop()
				end,
			}
		)

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
						local w = fixture(function(UI: FacetControls, _, T)
							return if kind == "color"
								then UI.ColorPicker "Picker" {
									value = C.cell(T.Color3.new(1, 0, 0)),
									isPresented = opened,
								}
								else UI.DateTimePicker "Picker" {
									value = C.cell({ year = 2026, month = 9, day = 30 }),
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
						Verify.expect(root:GetAttribute(key) ~= "sheet"):toBe(true)
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
						anchor.AbsolutePosition = T.Vector2.new(430, 800)
						anchor.AbsoluteSize = T.Vector2.new(300, 44)
						if kind == "color" then
							w.find("ShowSpectrum").AbsoluteSize = T.Vector2.new(340, 500)
						else
							w.find("Calendar").AbsoluteSize = T.Vector2.new(340, 500)
						end
						w.ctx.overlayParent.AbsoluteSize = T.Vector2.new(844, 390)
						panel.AbsoluteSize = T.Vector2.new(panel.Size.X.Offset, panel.Size.Y.Offset)
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
				local w = fixture(function(UI: FacetControls)
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
				w.ctx.overlayParent.AbsoluteSize = w.ctx.types.Vector2.new(300, 500)
				Verify.expect(panel.Size.X.Offset <= 300):toBe(true)
				Verify.expect((w.find("Panel"))):toBe(panel)
				w.stop()
			end,
		})
	end)
	return nil
end
