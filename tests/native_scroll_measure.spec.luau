--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	local FixtureNavigationTypes = require("../src/ui/navigation_types")
	local FixtureOverlayTypes = require("../src/ui/overlay_types")

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local Roblox = require("@lune/roblox")
	local UDim2, Vector2, Enum = Roblox.UDim2, Roblox.Vector2, Roblox.Enum

	local LONG = string.rep("Your lap will not count, and your place in the grid goes to the next driver. ", 40)
	local noop = function() end

	local function copy(Host: any): any
		return Host.TextLabel "Copy" {
			Text = LONG,
			TextWrapped = true,
			Size = UDim2.new(1, 0, 0, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
		}
	end

	local BUILDS: { [string]: (any, any) -> any } = {
		Dialog = function(UI: FacetControls, Host: RobloxHost)
			return UI.Dialog "Long" {
				isPresented = Compose.cell(true),
				onPresentedChange = noop,
				title = "Leave the race?",
				content = function(): Instance
					return copy(Host)
				end,
				actions = {
					{ id = "Stay", label = "Stay", role = "cancel" :: "cancel", onActivate = noop } :: FixtureOverlayTypes.DialogAction,
				},
			}
		end,
		Sheet = function(UI: FacetControls, Host: RobloxHost)
			return UI.Sheet "Long" {
				isPresented = Compose.cell(true),
				detent = Compose.cell("large"),
				title = "Race details",
				content = function(): Instance
					return copy(Host)
				end,
			}
		end,
		Popover = function(UI: FacetControls, Host: RobloxHost)
			return UI.Popover "Long" {
				isPresented = Compose.cell(true),
				source = { rect = { x = 100, y = 20, w = 40, h = 40 } },
				maxWidth = 320,
				maxHeight = 180,
				content = function(): Instance
					return copy(Host)
				end,
			}
		end,
		Alert = function(UI: FacetControls, Host: RobloxHost)
			return UI.Alert {
				isPresented = Compose.cell(true),
				title = "Confirm",
				content = function(): Instance
					return copy(Host)
				end,
				actions = {
					{ id = "Stay", label = "Stay", role = "cancel" :: "cancel" } :: FixtureNavigationTypes.AlertAction<any>,
				},
			}
		end,
	}

	local function bound(node: any): any
		local at = node.Parent
		while at and at:IsA("GuiObject") do
			if
				at:IsA("ScrollingFrame")
				or at.AutomaticSize == Enum.AutomaticSize.None
				or at.AutomaticSize == Enum.AutomaticSize.X
			then
				return at
			end
			at = at.Parent
		end
		return nil
	end

	verifyHarness:suite("native overlay bodies: long wrapped text measures outside the scroll window", function()
		verifyHarness:case("Sheet keeps a fill-height child scroll window inside its body", {
			id = "native_scroll_measure::native overlay bodies: long wrapped text measures outside the scroll window::Sheet keeps a fill-height child scroll window inside its body",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet "Nested" {
						isPresented = Compose.cell(true),
						detent = Compose.cell("large"),
						content = function(): Instance
							return Host.ScrollingFrame "Page" {
								Size = UDim2.fromScale(1, 1),
								AutomaticCanvasSize = Enum.AutomaticSize.Y,
							}
						end,
					}
				end)
				w.advance(1 / 60, 4)
				local body, page = w.find("SheetContent"), w.find("Page")
				body.AbsoluteWindowSize = Vector2.new(400, 500)
				Verify.expect(page.Size.Y.Scale):toBe(1)
				Verify.expect(w.find("SheetScrollViewport").Size.Y.Offset):toBe(484)
				body.AbsoluteWindowSize = Vector2.new(300, 250)
				Verify.expect(w.find("SheetScrollViewport").Size.Y.Offset):toBe(234)
				Verify.expect(page.AutomaticCanvasSize):toBe(Enum.AutomaticSize.Y)
				w.stop()
			end,
		})
		verifyHarness:case("Sheet preserves authored reactive scroll dimensions after viewport changes", {
			id = "native_scroll_measure::native overlay bodies: long wrapped text measures outside the scroll window::Sheet preserves authored reactive scroll dimensions after viewport changes",
			run = function()
				local authored = Compose.cell(UDim2.fromScale(1, 1))
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = Compose.cell(true),
						detent = Compose.cell("large"),
						content = function(): Instance
							return Host.ScrollingFrame "ReactivePage" { Size = authored }
						end,
					}
				end)
				w.advance(1 / 60, 4)
				local body, page = w.find("SheetContent"), w.find("ReactivePage")
				body.AbsoluteWindowSize = Vector2.new(400, 500)
				local nextSize = UDim2.new(0.5, 12, 0.75, -20)
				authored:set(nextSize)
				body.AbsoluteWindowSize = Vector2.new(300, 250)
				Verify.expect(page.Size):toBe(nextSize)
				w.stop()
			end,
		})

		for _, name in { "Dialog", "Sheet", "Popover", "Alert" } do
			verifyHarness:case(
				`{name}: the nearest fixed ancestor of the copy is taller than any text, and the canvas follows it`,
				{
					id = "native_scroll_measure::"
						.. "native overlay bodies: long wrapped text measures outside the scroll window"
						.. "::"
						.. `{name}: the nearest fixed ancestor of the copy is taller than any text, and the canvas follows it`,
					run = function()
						local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
							return Host.Frame({ BUILDS[name](UI, Host) })
						end)
						w.advance(1 / 60, 4)
						local label = w.find("Copy")
						Verify.expect(label ~= nil):toBe(true)
						local fixed = bound(label)
						Verify.expect(fixed ~= nil):toBe(true)
						Verify.expect((fixed:IsA("ScrollingFrame"))):toBe(false)
						Verify.expect(fixed.Size.Y.Offset >= 10000):toBe(true)
						local scroller = fixed.Parent
						Verify.expect((scroller:IsA("ScrollingFrame"))):toBe(true)
						Verify.expect(scroller.AutomaticCanvasSize):toBe(Enum.AutomaticSize.None)
						local flow = label.Parent
						while flow.Parent ~= fixed do
							flow = flow.Parent
						end
						flow.AbsoluteSize = Vector2.new(300, 2400)
						Verify.expect(scroller.CanvasSize.Y.Offset):toBe(2400)
						w.stop()
					end,
				}
			)
		end
	end)
end
