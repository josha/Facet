--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type MenuItem = typeof(require("@repo/tools/typecheck/aliases").MenuItem)

	local materialize = require("./lib/materialize")
	local fadeKit = require("./lib/fade")
	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local Vector2 = require("@lune/roblox").Vector2

	local FRAME = 1 / 60

	verifyHarness:suite("present at rest: help tooltip", function()
		verifyHarness:case("waits for all help text layout positions before entrance", {
			id = "native_motion_rest::present at rest: help tooltip::waits for all help text layout positions before entrance",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Button "Post" { label = "Post", help = { body = "Posts it", title = "Posting" } },
					}
				end)
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				w.gui.SelectedObject = w.find("Post")
				w.advance(0.5, 10)
				local panel, title = w.find("Help"), w.find("HelpTitle")
				w.size(panel, 140, 60)
				for step = 1, 5 do
					w.at(title, 8, 6 + step)
					w.advance(FRAME)
					Verify.expect(fadeKit.of(panel)):toBe(1)
				end
				w.advance(FRAME, 4)
				Verify.expect(fadeKit.of(panel) < 1):toBe(true)
				w.stop()
			end,
		})
		local function hovered(): any
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame({
					Name = "Screen",
					UI.Button "Post" { label = "Post", help = "Posts this avatar to the Marketplace" },
				})
			end)
			local post = w.find("Post")
			post.AbsolutePosition, post.AbsoluteSize = Vector2.new(300, 200), Vector2.new(80, 44)
			w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
			w.gui.SelectedObject = post
			w.advance(0.5, 10)
			return w
		end

		verifyHarness:case("keeps Help text at its rest origin through the whole entrance", {
			id = "native_motion_rest::present at rest: help tooltip::keeps Help text at its rest origin through the whole entrance",
			run = function()
				local w = hovered()
				local panel = w.find("Help")
				w.size(panel, 170, 64)
				local painted = 0
				for _ = 1, 30 do
					w.advance(FRAME)
					if fadeKit.of(panel) < 1 then
						Verify.expect(materialize.of(panel).Scale):toBe(1)
						Verify.expect(panel:FindFirstChild("PresentationContent", true)):toBe(nil)
						painted += 1
					end
				end
				Verify.expect(painted > 0):toBe(true)
				w.stop()
			end,
		})
		verifyHarness:case("holds scale 1 and stays transparent until the plate has rested one frame", {
			id = "native_motion_rest::present at rest: help tooltip::holds scale 1 and stays transparent until the plate has rested one frame",
			run = function()
				local w = hovered()
				local panel = w.find("Help")
				local scale = materialize.of(panel)
				panel.AbsoluteSize = Vector2.new(120, 30)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect((fadeKit.of(panel))):toBe(1)
				w.advance(FRAME)
				w.advance(FRAME)
				w.advance(FRAME)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect(fadeKit.of(panel) < 1):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("hidden tooltip bounds do not start its entrance", {
			id = "native_motion_rest::present at rest: help tooltip::hidden tooltip bounds do not start its entrance",
			run = function()
				local w = hovered()
				local panel = w.find("Help")
				panel.Visible = false
				panel.AbsoluteSize = Vector2.new(120, 30)
				w.advance(0.5, 30)
				Verify.expect(fadeKit.of(panel)):toBe(1)
				Verify.expect(materialize.of(panel).Scale):toBe(1)
				panel.Visible = true
				w.advance(FRAME, 3)
				Verify.expect(fadeKit.of(panel) < 1):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a scaled AbsoluteSize during the entrance does not move the plate", {
			id = "native_motion_rest::present at rest: help tooltip::a scaled AbsoluteSize during the entrance does not move the plate",
			run = function()
				local w = hovered()
				local panel = w.find("Help")
				local scale = materialize.of(panel)
				panel.AbsoluteSize = Vector2.new(120, 30)
				w.advance(FRAME, 1)
				w.advance(FRAME, 1)
				w.advance(FRAME, 1)
				local x, y = panel.Position.X.Offset, panel.Position.Y.Offset
				local ax, ay = panel.AnchorPoint.X, panel.AnchorPoint.Y
				panel.AbsoluteSize = Vector2.new(120 * scale.Scale, 30 * scale.Scale)
				w.advance(FRAME, 1)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect(fadeKit.of(panel) < 1):toBe(true)
				Verify.expect(panel.Position.X.Offset):toBe(x)
				Verify.expect(panel.Position.Y.Offset):toBe(y)
				Verify.expect(panel.AnchorPoint.X):toBe(ax)
				Verify.expect(panel.AnchorPoint.Y):toBe(ay)
				w.advance(1, 20)
				Verify.expect(scale.Scale):toBe(1)
				w.stop()
			end,
		})
		verifyHarness:case("holds the complete tooltip at its rested size while opacity changes", {
			id = "native_motion_rest::present at rest: help tooltip::holds the complete tooltip at its rested size while opacity changes",
			run = function()
				local w = hovered()
				local panel = w.find("Help")
				local scale = materialize.of(panel)
				panel.AbsoluteSize = Vector2.new(137.5, 63.2)
				w.advance(FRAME)
				w.advance(FRAME)
				w.advance(FRAME)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect(fadeKit.of(panel) < 1):toBe(true)
				Verify.expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.None)
				Verify.expect(panel:FindFirstChild("PresentationContent", true)):toBe(nil)
				Verify.expect(panel.Size.X.Offset):toBe(138)
				Verify.expect(panel.Size.Y.Offset):toBe(64)
				w.advance(1, 30)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.XY)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("present at rest: callout", function()
		local function presented(): any
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				local anchor = UI.Button "Plus" { label = "+" }
				return Host.Frame({
					Name = "Editor",
					Host.Frame({ Name = "Bar", anchor :: unknown }) :: unknown,
					UI.Callout "Tip" {
						anchor = anchor :: GuiObject,
						isPresented = true,
						content = function(): Instance
							return Host.TextLabel "Body" { Text = "Post Avatars to Marketplace" }
						end,
						onRetire = function() end,
					},
				})
			end, { runService = true })
			local plus = w.find("Plus")
			plus.AbsolutePosition, plus.AbsoluteSize = Vector2.new(300, 300), Vector2.new(44, 44)
			return w
		end

		verifyHarness:case("a scaled AbsoluteSize during the entrance does not move the plate or its tail", {
			id = "native_motion_rest::present at rest: callout::a scaled AbsoluteSize during the entrance does not move the plate or its tail",
			run = function()
				local w = presented()
				local panel, arrow = w.find("CalloutPanel"), w.find("Arrow")
				panel.AbsoluteSize = Vector2.new(280, 120)
				w.advance(FRAME, 1)
				w.advance(FRAME, 1)
				w.advance(FRAME, 1)
				local scale = materialize.of(panel)
				Verify.expect(scale.Scale < 1):toBe(true)
				local x, y = panel.Position.X.Offset, panel.Position.Y.Offset
				local tx, ty = arrow.Position.X.Offset, arrow.Position.Y.Offset
				panel.AbsoluteSize = Vector2.new(280 * scale.Scale, 120 * scale.Scale)
				w.advance(FRAME, 1)
				Verify.expect(scale.Scale < 1):toBe(true)
				Verify.expect(panel.Position.X.Offset):toBe(x)
				Verify.expect(panel.Position.Y.Offset):toBe(y)
				Verify.expect(arrow.Position.X.Offset):toBe(tx)
				Verify.expect(arrow.Position.Y.Offset):toBe(ty)
				Verify.expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.None)
				Verify.expect(panel.Size.Y.Offset):toBeCloseTo(120 * scale.Scale, 1)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("present at rest: anchored popover", function()
		for _, edge in { "top", "bottom", "leading", "trailing" } :: { "bottom" | "leading" | "top" | "trailing" } do
			verifyHarness:case(`keeps the {edge} pointer and border attached through entry and exit`, {
				id = "native_motion_rest::"
					.. "present at rest: anchored popover"
					.. "::"
					.. `keeps the {edge} pointer and border attached through entry and exit`,
				run = function()
					local open = Compose.cell(true)
					local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
						local anchor = UI.Button "Anchor" { label = "Save" }
						return Host.Frame {
							anchor :: unknown,
							UI.Popover "Pop" {
								isPresented = open,
								source = { node = anchor :: GuiObject },
								edge = edge :: "bottom" | "leading" | "top" | "trailing",
								content = function(): Instance
									return UI.Button "Save" {
										label = "Save",
										onActivate = function()
											open:set(false)
										end,
									}
								end,
							},
						}
					end, { runService = true })
					w.at(w.find("Anchor"), 350, 250)
					w.size(w.find("Anchor"), 40, 40)
					local panel, border, tail = w.find("Panel"), w.find("OutlineBoundary"), w.find("Tail")
					local borderFade = w.find("OutlineFade")
					local outline = w.find("Outline")
					w.size(panel, 200, 100)
					w.size(w.find("Flow"), 184, 84)
					local function check()
						Verify.expect(outline.Parent):toBe(border)
						Verify.expect(borderFade.Parent):toBe(panel.Parent)
						Verify.expect((border:IsDescendantOf(borderFade))):toBe(true)
						Verify.expect((outline:IsDescendantOf(panel))):toBe(false)
						Verify.expect(border.AnchorPoint):toBe(panel.AnchorPoint)
						Verify.expect(border.Position.X.Offset + borderFade.Position.X.Offset)
							:toBeCloseTo(panel.Position.X.Offset, 1)
						Verify.expect(border.Position.Y.Offset + borderFade.Position.Y.Offset)
							:toBeCloseTo(panel.Position.Y.Offset, 1)
						local scale = materialize.of(panel).Scale
						Verify.expect(border.Size.X.Offset):toBeCloseTo(200 * scale, 1)
						Verify.expect(border.Size.Y.Offset):toBeCloseTo(100 * scale, 1)
						local points = outline:GetControlPoints()
						local tip
						for _, point in points do
							local v = point.Position
							if v.X.Scale < 0 or v.X.Scale > 1 or v.Y.Scale < 0 or v.Y.Scale > 1 then
								tip = v
							end
						end
						Verify.expect(tip ~= nil):toBe(true)
						local x = borderFade.Position.X.Offset
							+ border.Position.X.Offset
							- border.AnchorPoint.X * border.Size.X.Offset
						local y = borderFade.Position.Y.Offset
							+ border.Position.Y.Offset
							- border.AnchorPoint.Y * border.Size.Y.Offset
						local half = tail.Size.X.Offset * math.sqrt(2) / 2
						local tipX = tail.Position.X.Offset
							+ (if edge == "leading" then half elseif edge == "trailing" then -half else 0)
						local tipY = tail.Position.Y.Offset
							+ (if edge == "top" then half elseif edge == "bottom" then -half else 0)
						Verify.expect(tipX):toBeCloseTo(x + tip.X.Scale * border.Size.X.Offset, 1.5)
						Verify.expect(tipY):toBeCloseTo(y + tip.Y.Scale * border.Size.Y.Offset, 1.5)
						Verify.expect((fadeKit.of(borderFade))):toBe(fadeKit.of(panel))
						local group = panel:FindFirstChild("Fade")
						Verify.expect(scale):toBe(1)
						Verify.expect(group.Parent):toBe(panel)
						Verify.expect(panel:FindFirstChild("PresentationPaint", true)):toBeNil()
					end
					Verify.expect((fadeKit.of(borderFade))):toBe(1)
					Verify.expect((outline:IsDescendantOf(borderFade:FindFirstChild("Fade")))):toBe(true)
					w.advance(FRAME, 3)
					check()
					Verify.expect(materialize.of(panel).Scale):toBe(1)
					for _ = 1, 12 do
						w.advance(FRAME)
						check()
					end
					Verify.expect(materialize.of(panel).Scale):toBe(1)
					w.find("Save").Activated:Fire()
					check()
					w.advance(FRAME)
					check()
					Verify.expect(materialize.of(panel).Scale):toBe(1)
					Verify.expect((panel:isDestroyed())):toBe(false)
					Verify.expect(fadeKit.of(borderFade) > 0):toBe(true)
					w.advance(0.2, 12)
					Verify.expect((panel:isDestroyed())):toBe(true)
					Verify.expect((border:isDestroyed())):toBe(true)
					Verify.expect((tail:isDestroyed())):toBe(true)
					w.stop()
				end,
			})
		end
		verifyHarness:case("keeps fractional native content bounds during materialization", {
			id = "native_motion_rest::present at rest: anchored popover::keeps fractional native content bounds during materialization",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Popover "Pop" {
						isPresented = Compose.cell(true),
						source = { rect = { x = 300, y = 200, w = 40, h = 40 } },
						content = function(): Instance
							return Host.TextLabel "Body" { Text = "Details" }
						end,
					}
				end)
				w.find("Panel").AbsoluteSize = Vector2.new(200, 100.95)
				w.find("Flow").AbsoluteSize = Vector2.new(184, 84.95)
				w.advance(FRAME, 3)
				local panel, flow = w.find("Panel"), w.find("Flow")
				local position = panel.Position
				for _ = 1, 24 do
					w.advance(FRAME)
					Verify.expect(panel.AbsoluteSize):toBe(Vector2.new(200, 100.95))
					Verify.expect(flow.AbsoluteSize):toBe(Vector2.new(184, 84.95))
					Verify.expect(panel.Position):toBe(position)
					Verify.expect(materialize.of(panel).Scale):toBe(1)
				end
				Verify.expect(w.find("PresentationSlotBounds")):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("placement reads the rested size while the panel fades in", {
			id = "native_motion_rest::present at rest: anchored popover::placement reads the rested size while the panel fades in",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Popover "Pop" {
						isPresented = Compose.cell(true),
						source = { rect = { x = 300, y = 200, w = 40, h = 40 } },
						edge = "bottom" :: "bottom",
						align = "center" :: "center",
						content = function(): Instance
							return Host.TextLabel "Body" { Text = "Details" }
						end,
					}
				end)
				local panel = w.find("Panel")
				panel.AbsoluteSize = Vector2.new(200, 100)
				w.find("Flow").AbsoluteSize = Vector2.new(184, 84)
				w.advance(FRAME, 1)
				w.advance(FRAME, 1)
				w.advance(FRAME, 1)
				local scale = materialize.of(panel)
				Verify.expect(scale.Scale):toBe(1)
				local x, y = panel.Position.X.Offset, panel.Position.Y.Offset
				panel.AbsoluteSize = Vector2.new(200 * scale.Scale, 100 * scale.Scale)
				Verify.expect(panel.Position.X.Offset):toBe(x)
				Verify.expect(panel.Position.Y.Offset):toBe(y)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("present at rest: sheet", function()
		verifyHarness:case("uses layout units for an adapted Popover", {
			id = "native_motion_rest::present at rest: sheet::uses layout units for an adapted Popover",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Popover {
						isPresented = Compose.cell(true),
						onPresentedChange = function() end,
						source = { rect = { x = 20, y = 30, w = 100, h = 40 } },
						content = function(): Instance
							return Host.TextLabel { Text = "Driver details" }
						end,
					}
				end, { motionLevel = "none" })
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				w.size(w.screen, 400 * 0.513, 800 * 0.513)
				local modal = w.find("Modal")
				Verify.expect(modal:GetAttribute("FacetRoute")):toBe("sheet")
				w.size(modal, 400 * 0.513, 800 * 0.513)
				for _, probe in w.findAll("LayoutUnit") do
					w.size(probe, 100 * 0.513, 0.513)
				end
				w.advance(0.5, 30)
				Verify.expect(w.find("SheetPanel").Size.X.Offset):toBe(400)
				w.stop()
			end,
		})
		verifyHarness:case("uses the mounted viewport before the first layout pass", {
			id = "native_motion_rest::present at rest: sheet::uses the mounted viewport before the first layout pass",
			run = function()
				local shown = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = shown,
						detent = Compose.cell("medium"),
						content = function(): Instance
							return Host.Frame {}
						end,
					}
				end)
				shown:set(true)
				local panel = w.find("SheetPanel")
				Verify.expect(panel.Size.X.Offset):toBe(560)
				Verify.expect(panel.Size.Y.Offset):toBe(300)
				w.stop()
			end,
		})
		verifyHarness:case("converts a scaled viewport to layout units", {
			id = "native_motion_rest::present at rest: sheet::converts a scaled viewport to layout units",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = Compose.cell(true),
						detent = Compose.cell("medium"),
						content = function(): Instance
							return Host.Frame {}
						end,
					}
				end, { motionLevel = "none" })
				w.size(w.find("Modal"), 600 * 0.513, 800 * 0.513)
				for _, probe in w.findAll("LayoutUnit") do
					w.size(probe, 100 * 0.513, 0.513)
				end
				w.advance(0.5, 30)
				local panel = w.find("SheetPanel")
				Verify.expect(panel.Size.X.Offset):toBe(560)
				Verify.expect(panel.Size.Y.Offset):toBe(400)
				w.stop()
			end,
		})
		verifyHarness:case("waits for child layout positions to hold before entrance", {
			id = "native_motion_rest::present at rest: sheet::waits for child layout positions to hold before entrance",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = Compose.cell(true),
						detent = Compose.cell("medium"),
						content = function(): Instance
							return Host.Frame { Name = "LateLayout" }
						end,
					}
				end)
				local panel, content = w.find("SheetPanel"), w.find("LateLayout")
				w.size(w.find("Modal"), 800, 600)
				w.size(panel, 400, 300)
				w.size(content, 200, 100)
				for step = 1, 5 do
					w.at(content, 16, 40 + step)
					w.advance(FRAME)
					Verify.expect(fadeKit.of(panel)):toBe(1)
				end
				w.advance(FRAME, 4)
				Verify.expect(fadeKit.of(panel) < 1):toBe(true)
				w.stop()
			end,
		})
		verifyHarness:case("keeps preparation transparent before normal motion starts", {
			id = "native_motion_rest::present at rest: sheet::keeps preparation transparent before normal motion starts",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						title = "Look summary",
						isPresented = Compose.cell(true),
						detent = Compose.cell("medium"),
						content = function(): Instance
							return Host.TextLabel { Text = "Appearance" }
						end,
					}
				end)
				local panel = w.find("SheetPanel")
				Verify.expect(fadeKit.of(panel)):toBe(1)
				w.size(panel, 400, 300)
				w.advance(FRAME, 1)
				Verify.expect(fadeKit.of(panel)):toBe(1)
				w.advance(0.5, 30)
				Verify.expect(fadeKit.of(panel)):toBe(0)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("rest tracker", function()
		verifyHarness:case("reduced motion also waits for the plate's size to hold, then shows it whole", {
			id = "native_motion_rest::rest tracker::reduced motion also waits for the plate's size to hold, then shows it whole",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ Name = "Screen", UI.Button "Post" { label = "Post", help = "Posts it" } })
				end, { motionLevel = "none" })
				local post = w.find("Post")
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				w.gui.SelectedObject = post
				w.advance(0.5, 10)
				local panel = w.find("Help")
				panel.AbsoluteSize = Vector2.new(120, 30)
				w.advance(FRAME)
				panel.AbsoluteSize = Vector2.new(130, 30)
				w.advance(FRAME)
				Verify.expect((fadeKit.of(panel))):toBe(1)
				w.advance(FRAME)
				w.advance(FRAME)
				Verify.expect((fadeKit.of(panel))):toBe(0)
				Verify.expect(materialize.of(panel).Scale):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case(
			"reduced motion switched on during the wait fades the plate in at scale 1 once its size holds",
			{
				id = "native_motion_rest::rest tracker::reduced motion switched on during the wait fades the plate in at scale 1 once its size holds",
				run = function()
					local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
						return Host.Frame({ Name = "Screen", UI.Button "Post" { label = "Post", help = "Posts it" } })
					end)
					w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
					w.gui.SelectedObject = w.find("Post")
					w.advance(0.5, 10)
					local panel = w.find("Help")
					w.advance(FRAME)
					Verify.expect((fadeKit.of(panel))):toBe(1)
					w.gui.ReducedMotionEnabled = true
					panel.AbsoluteSize = Vector2.new(120, 30)
					w.advance(FRAME, 3)
					Verify.expect(fadeKit.of(panel) < 1):toBe(true)
					Verify.expect(materialize.of(panel).Scale):toBe(1)
					w.advance(0.2, 12)
					Verify.expect((fadeKit.of(panel))):toBe(0)
					w.stop()
				end,
			}
		)

		verifyHarness:case("rest waits for a size that holds for a frame, not merely a filled one", {
			id = "native_motion_rest::rest tracker::rest waits for a size that holds for a frame, not merely a filled one",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ Name = "Screen", UI.Button "Post" { label = "Post", help = "Posts it" } })
				end)
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				w.gui.SelectedObject = w.find("Post")
				w.advance(0.5, 10)
				local panel = w.find("Help")
				local scale = materialize.of(panel)
				for index = 1, 5 do
					panel.AbsoluteSize = Vector2.new(100 + index, 30)
					w.advance(FRAME)
					Verify.expect(scale.Scale):toBe(1)
				end
				w.advance(FRAME)
				w.advance(FRAME)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect(fadeKit.of(panel) < 1):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a layout that never stops moving still enters after 0.25 seconds", {
			id = "native_motion_rest::rest tracker::a layout that never stops moving still enters after 0.25 seconds",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ Name = "Screen", UI.Button "Post" { label = "Post", help = "Posts it" } })
				end)
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				w.gui.SelectedObject = w.find("Post")
				w.advance(0.5, 10)
				local panel = w.find("Help")
				for index = 1, 20 do
					panel.AbsoluteSize = Vector2.new(100 + index, 30)
					w.advance(FRAME)
				end
				Verify.expect(fadeKit.of(panel) < 1):toBe(true)
				w.stop()
			end,
		})
	end)

	local worlds = require("./lib/content_world")
	local lune = require("@lune/roblox")
	local UDim2 = lune.UDim2

	local NESTED = {
		{ id = "plain", label = "Plain", onSelect = function() end } :: MenuItem,
		{
			id = "adjust",
			label = "Adjust",
			children = {
				{ id = "head", label = "Head", onSelect = function() end },
				{ id = "body", label = "Body", onSelect = function() end },
			},
		} :: MenuItem,
	}

	local function menu(spec: { [any]: any }): any
		spec.label = spec.label or "Options"
		return worlds.new(function(UI: FacetControls, Host: RobloxHost)
			return Host.Frame({ Name = "S", Size = UDim2.fromOffset(800, 600), UI.Menu("M")(spec) })
		end, {})
	end

	local function lay(world: any, panel: any, size: Vector2)
		local trigger = world.find("Trigger")
		trigger.AbsolutePosition, trigger.AbsoluteSize = Vector2.new(300, 300), Vector2.new(200, 40)
		local modal = panel.Parent
		while modal and modal.Parent and modal.Parent.ClassName ~= "ScreenGui" do
			modal = modal.Parent
		end
		modal.AbsoluteSize = Vector2.new(800, 600)
		panel.AbsoluteSize = size
		world.find("MenuRows", panel).AbsoluteSize = Vector2.new(size.X, size.Y)
	end

	verifyHarness:suite("present at rest: menu", function()
		verifyHarness:case("keeps the panel slot fixed while its paint appears", {
			id = "native_motion_rest::present at rest: menu::keeps the panel slot fixed while its paint appears",
			run = function()
				local world = menu({ items = NESTED, presentation = "menu" })
				world.find("Trigger").Activated:Fire()
				local panel = world.find("MenuPanel", world.screen.Parent)
				lay(world, panel, Vector2.new(220, 200))
				for _ = 1, 3 do
					world.engine.heartbeat:Fire(FRAME)
				end
				Verify.expect(panel.Size.X.Offset):toBe(220)
				Verify.expect(panel.Size.Y.Offset):toBe(200)
				Verify.expect(materialize.of(panel).Scale):toBe(1)
				world.stop()
			end,
		})
		verifyHarness:case("waits for rest at scale 1 then fades at the final anchor", {
			id = "native_motion_rest::present at rest: menu::waits for rest at scale 1 then fades at the final anchor",
			run = function()
				local world = menu({
					edge = "top" :: "top",
					align = "end" :: "end",
					items = NESTED,
					presentation = "menu" :: "menu",
				})
				world.find("Trigger").Activated:Fire()
				local panel = world.find("MenuPanel", world.screen.Parent)
				lay(world, panel, Vector2.new(220, 200))
				local scale = materialize.of(panel)
				Verify.expect(scale.Scale):toBe(1)
				world.engine.heartbeat:Fire(FRAME)
				world.engine.heartbeat:Fire(FRAME)
				world.engine.heartbeat:Fire(FRAME)
				Verify.expect(scale.Scale):toBe(1)
				local shrink = 1 - scale.Scale
				panel.AbsoluteSize = Vector2.new(220 * scale.Scale, 200 * scale.Scale)
				Verify.expect(materialize.position(panel).X.Offset):toBeCloseTo(280 + 220 * shrink, 1)
				Verify.expect(materialize.position(panel).Y.Offset):toBeCloseTo(96 + 200 * shrink, 2)
				world.stop()
			end,
		})

		verifyHarness:case("keeps the pinned point across fractional panel handoff", {
			id = "native_motion_rest::present at rest: menu::keeps the pinned point across fractional panel handoff",
			run = function()
				for _, height in { 52.0000076, 52.0000153 } do
					local world = menu({ edge = "top", align = "end", items = NESTED, presentation = "menu" })
					world.find("Trigger").Activated:Fire()
					local panel = world.find("MenuPanel", world.screen.Parent)
					lay(world, panel, Vector2.new(220.00003, height))
					for _ = 1, 24 do
						world.engine.heartbeat:Fire(FRAME)
						Verify.expect(panel.Position.X.Offset):toBe(500)
						Verify.expect(panel.Position.Y.Offset):toBe(296)
					end
					world.stop()
				end
			end,
		})

		verifyHarness:case("a submenu is measured at rest before its level animates", {
			id = "native_motion_rest::present at rest: menu::a submenu is measured at rest before its level animates",
			run = function()
				local world = menu({ items = NESTED, presentation = "menu" :: "menu" })
				world.find("Trigger").Activated:Fire()
				local panel = world.find("MenuPanel", world.screen.Parent)
				lay(world, panel, Vector2.new(220, 120))
				for _ = 1, 40 do
					world.engine.heartbeat:Fire(FRAME)
				end
				world.find("adjust", panel).Activated:Fire()
				local scale = materialize.of(panel)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect((fadeKit.of(world.find("MenuGroup", panel)))):toBe(1)
				world.find("MenuRows", panel).AbsoluteSize = Vector2.new(220, 90)
				panel.AbsoluteSize = Vector2.new(220, 90)
				world.engine.heartbeat:Fire(FRAME)
				world.engine.heartbeat:Fire(FRAME)
				world.engine.heartbeat:Fire(FRAME)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect(panel.Size.Y.Offset):toBe(90)
				Verify.expect(panel:FindFirstChild("PresentationPaint", true)):toBeNil()
				panel.AbsoluteSize = Vector2.new(220 * scale.Scale, 90 * scale.Scale)
				world.find("MenuRows", panel).AbsoluteSize = Vector2.new(220 * scale.Scale, 90 * scale.Scale)
				Verify.expect(panel.Size.Y.Offset):toBe(90)
				Verify.expect(panel:FindFirstChild("PresentationPaint", true)):toBeNil()
				world.stop()
			end,
		})
	end)

	verifyHarness:suite("present at rest: mobile controls", function()
		verifyHarness:case("keeps the colour panel transparent while its swatches reflow", {
			id = "native_motion_rest::present at rest: mobile controls::keeps the colour panel transparent while its swatches reflow",
			run = function()
				local w = overlay.new(function(UI: FacetControls)
					return UI.ColorPicker "Colour" {
						value = Compose.cell(require("@lune/roblox").Color3.new(1, 0, 0)),
						onChange = function() end,
					}
				end, { runService = true })
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				w.size(w.screen, 390, 844)
				w.find("Well").Activated:Fire()
				local panel, technique = w.find("Panel"), w.find("Technique")
				for _, node in panel:GetDescendants() do
					if node:IsA("TextLabel") or node:IsA("TextButton") or node:IsA("TextBox") then
						w.size(node, 40, 16)
					end
				end
				w.size(technique, 350, 220)
				Verify.expect((fadeKit.of(panel))):toBe(1)
				w.advance(FRAME)
				w.size(technique, 330, 264)
				w.advance(FRAME)
				Verify.expect((fadeKit.of(panel))):toBe(1)
				for _ = 1, 4 do
					w.advance(FRAME)
				end
				Verify.expect((fadeKit.of(panel))):toBe(0)
				Verify.expect(w.find("DismissOutside").BorderSizePixel):toBe(0)
				w.stop()
			end,
		})
	end)
end
