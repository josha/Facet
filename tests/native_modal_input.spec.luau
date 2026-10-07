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

	local function bodyOf(w: any, name: string): any
		return overlay.find(modalOf(w, name), "Body")
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

		verifyHarness:case("stacked modals hold every scroller outside the top one and restore each exact value", {
			id = "native_modal_input::native modal: the scrim sinks input::stacked modals hold every scroller outside the top one and restore each exact value",
			run = function()
				local first, second = Compose.cell(false), Compose.cell(false)
				local late = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Host.ScrollingFrame "Grid" { ScrollingEnabled = true } :: unknown,
						Host.ScrollingFrame "Frozen" { ScrollingEnabled = false },
						Compose.show(late, function()
							return Host.ScrollingFrame "Late" { ScrollingEnabled = true }
						end),
						dialog(UI, Host, "First", first),
						dialog(UI, Host, "Second", second),
					})
				end)
				local grid, frozen = w.find("Grid"), w.find("Frozen")
				first:set(true)
				local firstBody = bodyOf(w, "First")
				Verify.expect(grid.ScrollingEnabled):toBe(false)
				Verify.expect(frozen.ScrollingEnabled):toBe(false)
				Verify.expect(firstBody.ScrollingEnabled):toBe(true)
				second:set(true)
				local secondBody = bodyOf(w, "Second")
				Verify.expect(firstBody.ScrollingEnabled):toBe(false)
				Verify.expect(secondBody.ScrollingEnabled):toBe(true)
				late:set(true)
				local lateFrame = w.find("Late")
				Verify.expect(lateFrame.ScrollingEnabled):toBe(false)
				second:set(false)
				Verify.expect(firstBody.ScrollingEnabled):toBe(true)
				Verify.expect(grid.ScrollingEnabled):toBe(false)
				Verify.expect(lateFrame.ScrollingEnabled):toBe(false)
				first:set(false)
				Verify.expect(grid.ScrollingEnabled):toBe(true)
				Verify.expect(frozen.ScrollingEnabled):toBe(false)
				Verify.expect(lateFrame.ScrollingEnabled):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a scroller that leaves while held gets its value back, and closing out of order restores", {
			id = "native_modal_input::native modal: the scrim sinks input::a scroller that leaves while held gets its value back, and closing out of order restores",
			run = function()
				local first, second = Compose.cell(true), Compose.cell(false)
				local kept = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Compose.show(kept, function()
							return Host.ScrollingFrame "Feed" { ScrollingEnabled = true }
						end) :: unknown,
						Host.ScrollingFrame "Grid" { ScrollingEnabled = true },
						dialog(UI, Host, "First", first),
						dialog(UI, Host, "Second", second),
					})
				end)
				local feed, grid = w.find("Feed"), w.find("Grid")
				Verify.expect(feed.ScrollingEnabled):toBe(false)
				kept:set(false)
				Verify.expect(feed.ScrollingEnabled):toBe(true)
				second:set(true)
				first:set(false)
				Verify.expect(grid.ScrollingEnabled):toBe(false)
				Verify.expect(bodyOf(w, "Second").ScrollingEnabled):toBe(true)
				second:set(false)
				Verify.expect(grid.ScrollingEnabled):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("an exiting modal gives scrolling back at once, and a second layer is never touched", {
			id = "native_modal_input::native modal: the scrim sinks input::an exiting modal gives scrolling back at once, and a second layer is never touched",
			run = function()
				local open = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Host.ScrollingFrame "Grid" { ScrollingEnabled = true } :: unknown,
						dialog(UI, Host, "About", open),
					})
				end)
				local other = overlay.new(function(_, Host: RobloxHost)
					return Host.ScrollingFrame "Elsewhere" { ScrollingEnabled = true }
				end)
				local grid = w.find("Grid")
				open:set(true)
				w.advance(0.3, 18)
				Verify.expect(grid.ScrollingEnabled):toBe(false)
				Verify.expect(other.find("Elsewhere").ScrollingEnabled):toBe(true)
				open:set(false)
				Verify.expect(modalOf(w, "About") ~= nil):toBe(true)
				Verify.expect(grid.ScrollingEnabled):toBe(true)
				w.advance(0.3, 18)
				Verify.expect((modalOf(w, "About"))):toBeNil()
				Verify.expect(grid.ScrollingEnabled):toBe(true)
				w.stop()
				other.stop()
			end,
		})
	end)
end
