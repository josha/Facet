--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")

local function dialog(UI: any, Host: any, name: string, open: any): any
	return UI.Dialog(name)({
		isPresented = open,
		onPresentedChange = function(value: boolean)
			open:set(value)
		end,
		title = name,
		content = function()
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

t.describe("native modal: the scrim sinks input", function()
	t.it("the modal root and its full-screen scrim are Active", function()
		local open = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({ dialog(UI, Host, "About", open) })
		end)
		local modal = modalOf(w, "About")
		t.expect(modal.Active).toBe(true)
		t.expect(overlay.find(modal, "DismissOutside").Active).toBe(true)
		w.stop()
	end)

	t.it("stacked modals hold every scroller outside the top one and restore each exact value", function()
		local first, second = Compose.cell(false), Compose.cell(false)
		local late = Compose.cell(false)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Host.ScrollingFrame "Grid" { ScrollingEnabled = true },
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
		t.expect(grid.ScrollingEnabled).toBe(false)
		t.expect(frozen.ScrollingEnabled).toBe(false)
		t.expect(firstBody.ScrollingEnabled).toBe(true)
		second:set(true)
		local secondBody = bodyOf(w, "Second")
		t.expect(firstBody.ScrollingEnabled).toBe(false)
		t.expect(secondBody.ScrollingEnabled).toBe(true)
		late:set(true)
		local lateFrame = w.find("Late")
		t.expect(lateFrame.ScrollingEnabled).toBe(false)
		second:set(false)
		t.expect(firstBody.ScrollingEnabled).toBe(true)
		t.expect(grid.ScrollingEnabled).toBe(false)
		t.expect(lateFrame.ScrollingEnabled).toBe(false)
		first:set(false)
		t.expect(grid.ScrollingEnabled).toBe(true)
		t.expect(frozen.ScrollingEnabled).toBe(false)
		t.expect(lateFrame.ScrollingEnabled).toBe(true)
		w.stop()
	end)

	t.it("a scroller that leaves while held gets its value back, and closing out of order restores", function()
		local first, second = Compose.cell(true), Compose.cell(false)
		local kept = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Compose.show(kept, function()
					return Host.ScrollingFrame "Feed" { ScrollingEnabled = true }
				end),
				Host.ScrollingFrame "Grid" { ScrollingEnabled = true },
				dialog(UI, Host, "First", first),
				dialog(UI, Host, "Second", second),
			})
		end)
		local feed, grid = w.find("Feed"), w.find("Grid")
		t.expect(feed.ScrollingEnabled).toBe(false)
		kept:set(false)
		t.expect(feed.ScrollingEnabled).toBe(true)
		second:set(true)
		first:set(false)
		t.expect(grid.ScrollingEnabled).toBe(false)
		t.expect(bodyOf(w, "Second").ScrollingEnabled).toBe(true)
		second:set(false)
		t.expect(grid.ScrollingEnabled).toBe(true)
		w.stop()
	end)

	t.it("an exiting modal gives scrolling back at once, and a second layer is never touched", function()
		local open = Compose.cell(false)
		local w = overlay.new(function(UI, Host)
			return Host.Frame({
				Host.ScrollingFrame "Grid" { ScrollingEnabled = true },
				dialog(UI, Host, "About", open),
			})
		end)
		local other = overlay.new(function(_, Host)
			return Host.ScrollingFrame "Elsewhere" { ScrollingEnabled = true }
		end)
		local grid = w.find("Grid")
		open:set(true)
		w.advance(0.3, 18)
		t.expect(grid.ScrollingEnabled).toBe(false)
		t.expect(other.find("Elsewhere").ScrollingEnabled).toBe(true)
		open:set(false)
		t.expect(modalOf(w, "About") ~= nil).toBe(true)
		t.expect(grid.ScrollingEnabled).toBe(true)
		w.advance(0.3, 18)
		t.expect(modalOf(w, "About")).toBeNil()
		t.expect(grid.ScrollingEnabled).toBe(true)
		w.stop()
		other.stop()
	end)
end)
