--!strict
local t = require("./lib/testkit")
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
	Dialog = function(UI, Host)
		return UI.Dialog "Long" {
			isPresented = Compose.cell(true),
			onPresentedChange = noop,
			title = "Leave the race?",
			content = function()
				return copy(Host)
			end,
			actions = { { id = "Stay", label = "Stay", role = "cancel", onActivate = noop } },
		}
	end,
	Sheet = function(UI, Host)
		return UI.Sheet "Long" {
			isPresented = Compose.cell(true),
			detent = Compose.cell("large"),
			title = "Race details",
			content = function()
				return copy(Host)
			end,
		}
	end,
	Popover = function(UI, Host)
		return UI.Popover "Long" {
			isPresented = Compose.cell(true),
			source = { rect = { x = 100, y = 20, w = 40, h = 40 } },
			maxWidth = 320,
			maxHeight = 180,
			content = function()
				return copy(Host)
			end,
		}
	end,
	Alert = function(UI, Host)
		return UI.Alert {
			isPresented = Compose.cell(true),
			title = "Confirm",
			content = function()
				return copy(Host)
			end,
			actions = { { id = "Stay", label = "Stay", role = "cancel" } },
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

t.describe("native overlay bodies: long wrapped text measures outside the scroll window", function()
	for _, name in { "Dialog", "Sheet", "Popover", "Alert" } do
		t.it(
			`{name}: the nearest fixed ancestor of the copy is taller than any text, and the canvas follows it`,
			function()
				local w = overlay.new(function(UI, Host)
					return Host.Frame({ BUILDS[name](UI, Host) })
				end)
				w.advance(1 / 60, 4)
				local label = w.find("Copy")
				t.expect(label ~= nil).toBe(true)
				local fixed = bound(label)
				t.expect(fixed ~= nil).toBe(true)
				t.expect(fixed:IsA("ScrollingFrame")).toBe(false)
				t.expect(fixed.Size.Y.Offset >= 10000).toBe(true)
				local scroller = fixed.Parent
				t.expect(scroller:IsA("ScrollingFrame")).toBe(true)
				t.expect(scroller.AutomaticCanvasSize).toBe(Enum.AutomaticSize.None)
				local flow = label.Parent
				while flow.Parent ~= fixed do
					flow = flow.Parent
				end
				flow.AbsoluteSize = Vector2.new(300, 2400)
				t.expect(scroller.CanvasSize.Y.Offset).toBe(2400)
				w.stop()
			end
		)
	end
end)
