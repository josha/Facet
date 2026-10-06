--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness, tier: string)
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
				Verify.expect(scale.Scale < 1):toBe(true)
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
				Verify.expect(scale.Scale < 1):toBe(true)
				Verify.expect(panel.Position.X.Offset):toBe(x)
				Verify.expect(panel.Position.Y.Offset):toBe(y)
				Verify.expect(panel.AnchorPoint.X):toBe(ax)
				Verify.expect(panel.AnchorPoint.Y):toBe(ay)
				w.advance(1, 20)
				Verify.expect(scale.Scale):toBe(1)
				w.stop()
			end,
		})
		verifyHarness:case("holds content at its rested size while the surrounding plate grows", {
			id = "native_motion_rest::present at rest: help tooltip::holds content at its rested size while the surrounding plate grows",
			run = function()
				local w = hovered()
				local panel = w.find("Help")
				local scale = materialize.of(panel)
				panel.AbsoluteSize = Vector2.new(137.5, 63.2)
				w.advance(FRAME)
				w.advance(FRAME)
				w.advance(FRAME)
				Verify.expect(scale.Scale < 1):toBe(true)
				Verify.expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.None)
				Verify.expect(panel:FindFirstChild("PresentationContent", true).Size.X.Offset):toBe(122)
				Verify.expect(panel:FindFirstChild("PresentationContent", true).Size.Y.Offset):toBe(52)
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
						if scale < 1 and group then
							Verify.expect(group.Size):toBe(w.engine.types.UDim2.fromOffset(184, 84))
							Verify.expect(group.AutomaticSize):toBe(w.Enum.AutomaticSize.None)
							Verify.expect(panel.ClipsDescendants):toBe(true)
							local borderGroup = borderFade:FindFirstChild("Fade")
							Verify.expect((outline:IsDescendantOf(borderGroup)))
								:toBe(panel:FindFirstChild("PresentationContent", true):IsDescendantOf(group))
						end
					end
					Verify.expect((fadeKit.of(borderFade))):toBe(1)
					Verify.expect((outline:IsDescendantOf(borderFade:FindFirstChild("Fade")))):toBe(true)
					w.advance(FRAME, 3)
					check()
					Verify.expect(materialize.of(panel).Scale < 1):toBe(true)
					for _ = 1, 12 do
						w.advance(FRAME)
						check()
					end
					Verify.expect(materialize.of(panel).Scale):toBe(1)
					w.find("Save").Activated.fire()
					check()
					w.advance(FRAME)
					check()
					Verify.expect(materialize.of(panel).Scale < 1):toBe(true)
					Verify.expect((panel.isDestroyed())):toBe(false)
					Verify.expect(fadeKit.of(borderFade) > 0):toBe(true)
					w.advance(0.2, 12)
					Verify.expect((panel.isDestroyed())):toBe(true)
					Verify.expect((border.isDestroyed())):toBe(true)
					Verify.expect((tail.isDestroyed())):toBe(true)
					w.stop()
				end,
			})
		end
		verifyHarness:case("placement reads the rested size while the panel scales in", {
			id = "native_motion_rest::present at rest: anchored popover::placement reads the rested size while the panel scales in",
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
				Verify.expect(scale.Scale < 1):toBe(true)
				local x, y = panel.Position.X.Offset, panel.Position.Y.Offset
				panel.AbsoluteSize = Vector2.new(200 * scale.Scale, 100 * scale.Scale)
				Verify.expect(panel.Position.X.Offset):toBe(x)
				Verify.expect(panel.Position.Y.Offset):toBe(y)
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
				Verify.expect(scale.Scale < 1):toBe(true)
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
		verifyHarness:case("waits for rest at scale 1, then scales about the rested corner", {
			id = "native_motion_rest::present at rest: menu::waits for rest at scale 1, then scales about the rested corner",
			run = function()
				local world = menu({
					edge = "top" :: "top",
					align = "end" :: "end",
					items = NESTED,
					presentation = "menu" :: "menu",
				})
				world.find("Trigger").Activated.fire()
				local panel = world.find("MenuPanel", world.screen.Parent)
				lay(world, panel, Vector2.new(220, 200))
				local scale = materialize.of(panel)
				Verify.expect(scale.Scale):toBe(1)
				world.engine.heartbeat.fire(FRAME)
				world.engine.heartbeat.fire(FRAME)
				world.engine.heartbeat.fire(FRAME)
				Verify.expect(scale.Scale < 1):toBe(true)
				local shrink = 1 - scale.Scale
				panel.AbsoluteSize = Vector2.new(220 * scale.Scale, 200 * scale.Scale)
				Verify.expect(materialize.position(panel).X.Offset):toBeCloseTo(280 + 220 * shrink, 1)
				Verify.expect(materialize.position(panel).Y.Offset):toBeCloseTo(96 + 200 * shrink, 2)
				world.stop()
			end,
		})

		verifyHarness:case("a submenu is measured at rest before its level animates", {
			id = "native_motion_rest::present at rest: menu::a submenu is measured at rest before its level animates",
			run = function()
				local world = menu({ items = NESTED, presentation = "menu" :: "menu" })
				world.find("Trigger").Activated.fire()
				local panel = world.find("MenuPanel", world.screen.Parent)
				lay(world, panel, Vector2.new(220, 120))
				for _ = 1, 40 do
					world.engine.heartbeat.fire(FRAME)
				end
				world.find("adjust", panel).Activated.fire()
				local scale = materialize.of(panel)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect((fadeKit.of(world.find("MenuGroup", panel)))):toBe(1)
				world.find("MenuRows", panel).AbsoluteSize = Vector2.new(220, 90)
				panel.AbsoluteSize = Vector2.new(220, 90)
				world.engine.heartbeat.fire(FRAME)
				world.engine.heartbeat.fire(FRAME)
				world.engine.heartbeat.fire(FRAME)
				Verify.expect(scale.Scale < 1):toBe(true)
				Verify.expect(panel.Size.Y.Offset):toBeCloseTo(90 * scale.Scale, 1)
				panel.AbsoluteSize = Vector2.new(220 * scale.Scale, 90 * scale.Scale)
				world.find("MenuRows", panel).AbsoluteSize = Vector2.new(220 * scale.Scale, 90 * scale.Scale)
				Verify.expect(panel.Size.Y.Offset):toBeCloseTo(90 * scale.Scale, 1)
				world.stop()
			end,
		})
	end)
end
