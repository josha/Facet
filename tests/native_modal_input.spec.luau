--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")

	local function dialog(UI: any, Host: any, name: string, open: any): any
		return UI.Dialog(name)({
			isPresented = open,
			onPresentedChange = function(value: boolean)
				open:set(value)
			end,
			title = name,
			content = function(): Instance
				return Host.TextLabel "Line" { Text = name }
			end,
		})
	end

	local function modalOf(w: any, name: string): any
		for _, modal in w.findAll("DialogModal") do
			if overlay.find(modal, "Title").Text == name then
				return modal
			end
		end
		return nil
	end

	verifyHarness:suite("native modal: the scrim sinks input", function()
		verifyHarness:case("the modal root and its full-screen scrim are Active", {
			id = "native_modal_input::native modal: the scrim sinks input::the modal root and its full-screen scrim are Active",
			run = function()
				local open = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ dialog(UI, Host, "About", open) })
				end)
				local modal = modalOf(w, "About")
				Verify.expect(modal.Active):toBe(true)
				Verify.expect(overlay.find(modal, "DismissOutside").Active):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("the scrim covers asymmetric core UI insets and follows top bar changes", {
			id = "native_modal_input::native modal: the scrim sinks input::the scrim covers asymmetric core UI insets and follows top bar changes",
			run = function()
				local open = Compose.cell(false)
				local near, far
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine, gui)
					near, far = engine.types.Vector2.new(0, 87), engine.types.Vector2.new(0, 0)
					gui.GetGuiInset = function()
						return near, far
					end
					return Host.Frame({ dialog(UI, Host, "About", open) })
				end)
				w.screen.ScreenInsets = w.Enum.ScreenInsets.CoreUISafeInsets
				w.screen.IgnoreGuiInset = false
				open:set(true)
				local scrim = w.find("DismissOutside")
				Verify.expect(scrim.Position):toBe(w.engine.types.UDim2.fromOffset(0, -87))
				Verify.expect(scrim.Size):toBe(w.engine.types.UDim2.new(1, 0, 1, 87))
				near, far = w.Vector2.new(12, 60), w.Vector2.new(8, 20)
				w.gui.TopbarInset = w.engine.types.Rect.new(0, 0, 100, 60)
				Verify.expect(scrim.Position):toBe(w.engine.types.UDim2.fromOffset(-12, -60))
				Verify.expect(scrim.Size):toBe(w.engine.types.UDim2.new(1, 20, 1, 80))
				w.stop()
			end,
		})
	end)
end
