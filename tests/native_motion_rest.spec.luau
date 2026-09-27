--!strict
local t = require("./lib/testkit")
local fadeKit = require("./lib/fade")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local Vector2 = require("@lune/roblox").Vector2

local FRAME = 1 / 60

t.describe("present at rest: help tooltip", function()
	local function hovered(): any
		local w = overlay.new(function(UI, Host)
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

	t.it("holds scale 1 and stays transparent until the plate has rested one frame", function()
		local w = hovered()
		local panel = w.find("Help")
		local scale = panel:FindFirstChildWhichIsA("UIScale")
		panel.AbsoluteSize = Vector2.new(120, 30)
		t.expect(scale.Scale).toBe(1)
		t.expect(fadeKit.of(panel)).toBe(1)
		w.advance(FRAME)
		w.advance(FRAME)
		w.advance(FRAME)
		t.expect(scale.Scale < 1).toBe(true)
		w.stop()
	end)

	t.it("a scaled AbsoluteSize during the entrance does not move the plate", function()
		local w = hovered()
		local panel = w.find("Help")
		local scale = panel:FindFirstChildWhichIsA("UIScale")
		panel.AbsoluteSize = Vector2.new(120, 30)
		w.advance(FRAME, 1)
		w.advance(FRAME, 1)
		w.advance(FRAME, 1)
		local x, y = panel.Position.X.Offset, panel.Position.Y.Offset
		local ax, ay = panel.AnchorPoint.X, panel.AnchorPoint.Y
		panel.AbsoluteSize = Vector2.new(120 * scale.Scale, 30 * scale.Scale)
		w.advance(FRAME, 1)
		t.expect(scale.Scale < 1).toBe(true)
		t.expect(panel.Position.X.Offset).toBe(x)
		t.expect(panel.Position.Y.Offset).toBe(y)
		t.expect(panel.AnchorPoint.X).toBe(ax)
		t.expect(panel.AnchorPoint.Y).toBe(ay)
		w.advance(1, 20)
		t.expect(scale.Scale).toBe(1)
		w.stop()
	end)
end)

t.describe("present at rest: callout", function()
	local function presented(): any
		local w = overlay.new(function(UI, Host)
			local anchor = UI.Button "Plus" { label = "+" }
			return Host.Frame({
				Name = "Editor",
				Host.Frame({ Name = "Bar", anchor }),
				UI.Callout "Tip" {
					anchor = anchor,
					isPresented = true,
					content = function()
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

	t.it("a scaled AbsoluteSize during the entrance does not move the plate or its tail", function()
		local w = presented()
		local panel, arrow = w.find("CalloutPanel"), w.find("Arrow")
		panel.AbsoluteSize = Vector2.new(280, 120)
		w.advance(FRAME, 1)
		w.advance(FRAME, 1)
		w.advance(FRAME, 1)
		local scale = panel:FindFirstChildWhichIsA("UIScale")
		t.expect(scale.Scale < 1).toBe(true)
		local x, y = panel.Position.X.Offset, panel.Position.Y.Offset
		local tx, ty = arrow.Position.X.Offset, arrow.Position.Y.Offset
		panel.AbsoluteSize = Vector2.new(280 * scale.Scale, 120 * scale.Scale)
		w.advance(FRAME, 1)
		t.expect(scale.Scale < 1).toBe(true)
		t.expect(panel.Position.X.Offset).toBe(x)
		t.expect(panel.Position.Y.Offset).toBe(y)
		t.expect(arrow.Position.X.Offset).toBe(tx)
		t.expect(arrow.Position.Y.Offset).toBe(ty)
		w.stop()
	end)
end)

t.describe("present at rest: anchored popover", function()
	t.it("placement reads the rested size while the panel scales in", function()
		local w = overlay.new(function(UI, Host)
			return UI.Popover "Pop" {
				isPresented = Compose.cell(true),
				source = { rect = { x = 300, y = 200, w = 40, h = 40 } },
				edge = "bottom",
				align = "center",
				content = function()
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
		local scale = panel:FindFirstChild("PresentationScale")
		t.expect(scale.Scale < 1).toBe(true)
		local x, y = panel.Position.X.Offset, panel.Position.Y.Offset
		panel.AbsoluteSize = Vector2.new(200 * scale.Scale, 100 * scale.Scale)
		t.expect(panel.Position.X.Offset).toBe(x)
		t.expect(panel.Position.Y.Offset).toBe(y)
		w.stop()
	end)
end)

t.describe("rest tracker", function()
	t.it("reduced motion is at rest at once and never waits", function()
		local w = overlay.new(function(UI, Host)
			return Host.Frame({ Name = "Screen", UI.Button "Post" { label = "Post", help = "Posts it" } })
		end, { reducedMotion = true })
		local post = w.find("Post")
		w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
		w.gui.SelectedObject = post
		w.advance(0.5, 10)
		local panel = w.find("Help")
		t.expect(fadeKit.of(panel)).toBe(0)
		t.expect(panel:FindFirstChildWhichIsA("UIScale").Scale).toBe(1)
		w.stop()
	end)

	t.it("a layout that never stops moving still enters after 0.25 seconds", function()
		local w = overlay.new(function(UI, Host)
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
		t.expect(fadeKit.of(panel) < 1).toBe(true)
		w.stop()
	end)
end)
