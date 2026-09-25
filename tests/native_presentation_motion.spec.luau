--!strict
local t = require("./lib/testkit")
local Compose = require("../src/vendor/compose/core")
local overlay = require("./lib/overlay_world")
local Vector2 = require("@lune/roblox").Vector2

local FRAME = 1 / 60

local function within(node: any, ancestor: any): boolean
	while node do
		if node == ancestor then
			return true
		end
		node = node.Parent
	end
	return false
end

local function dialogWorld(options: any?): (any, any)
	local open = Compose.cell(false)
	local w = overlay.new(function(UI, Host, _, gui)
		local opener = UI.Button "Opener" { label = "About" }
		gui.SelectedObject = opener
		return Host.Frame({
			opener,
			UI.Dialog "About" {
				isPresented = open,
				onPresentedChange = function(value: boolean)
					open:set(value)
				end,
				title = "About",
				content = function()
					return Host.TextLabel "Line" { Text = "Three apps." }
				end,
				actions = {
					{
						id = "Done",
						label = "Done",
						role = "cancel",
						onActivate = function()
							open:set(false)
						end,
					},
				},
			},
		})
	end, options)
	return w, open
end

local function fadeOf(w: any): number
	return w.find("ScrimFade").Transparency.Keypoints[1].Value
end

t.describe("presentation motion: Dialog and CollapsibleView", function()
	t.it("a dialog scales from 0.94 and fades in with its scrim, frame by frame, in 0.2 seconds", function()
		local w, open = dialogWorld()
		open:set(true)
		local panel = w.find("Panel")
		local scale = overlay.find(panel, "PresentationScale")
		t.expect(panel.ClassName).toBe("CanvasGroup")
		t.expect(scale.Scale).toBe(0.94)
		t.expect(panel.GroupTransparency).toBe(1)
		t.expect(fadeOf(w)).toBe(1)
		local lastScale, lastFade = scale.Scale, panel.GroupTransparency
		for _ = 1, 11 do
			w.advance(FRAME)
			t.expect(scale.Scale > lastScale).toBe(true)
			t.expect(panel.GroupTransparency < lastFade).toBe(true)
			t.expect(fadeOf(w)).toBeCloseTo(panel.GroupTransparency, 1e-6)
			lastScale, lastFade = scale.Scale, panel.GroupTransparency
		end
		w.advance(0.05, 3)
		t.expect(scale.Scale).toBe(1)
		t.expect(panel.GroupTransparency).toBe(0)
		t.expect(fadeOf(w)).toBe(0)
		w.stop()
	end)

	t.it("a dismissed dialog reverses faster, stops taking input and hands the selection back at once", function()
		local w, open = dialogWorld()
		open:set(true)
		w.advance(0.25, 15)
		local panel = w.find("Panel")
		t.expect(within(w.gui.SelectedObject, panel)).toBe(true)
		open:set(false)
		t.expect(w.find("DialogModal").Interactable).toBe(false)
		t.expect(w.gui.SelectedObject).toBe(w.find("Opener"))
		local last = panel.GroupTransparency
		for _ = 1, 6 do
			w.advance(FRAME)
			t.expect(panel.GroupTransparency > last).toBe(true)
			last = panel.GroupTransparency
			t.expect(panel.isDestroyed()).toBe(false)
		end
		w.advance(0.06, 4)
		t.expect(panel.isDestroyed()).toBe(true)
		t.expect(w.gui.SelectedObject).toBe(w.find("Opener"))
		w.stop()
	end)

	t.it("reduced motion presents and dismisses a dialog at once", function()
		local w, open = dialogWorld({ reducedMotion = true })
		open:set(true)
		local panel = w.find("Panel")
		t.expect(overlay.find(panel, "PresentationScale").Scale).toBe(1)
		t.expect(panel.GroupTransparency).toBe(0)
		w.advance(0.1, 6)
		open:set(false)
		t.expect(panel.isDestroyed()).toBe(true)
		w.stop()
	end)

	t.it("a collapsible view presents its surface with the dialog motion", function()
		local expanded = Compose.cell(false)
		local w = overlay.new(function(UI)
			return UI.CollapsibleView "Tips" {
				label = "Tips",
				expanded = expanded,
				content = function()
					return UI.Button "Detail" { label = "Detail" }
				end,
			}
		end)
		expanded:set(true)
		local surface = w.find("ExpandedPresentation")
		local scale = overlay.find(surface, "PresentationScale")
		t.expect(surface.ClassName).toBe("CanvasGroup")
		t.expect(scale.Scale).toBe(0.94)
		t.expect(surface.GroupTransparency).toBe(1)
		w.advance(0.1, 6)
		t.expect(scale.Scale > 0.94 and scale.Scale < 1).toBe(true)
		w.advance(0.15, 9)
		t.expect(scale.Scale).toBe(1)
		t.expect(surface.GroupTransparency).toBe(0)
		expanded:set(false)
		w.advance(0.1, 6)
		t.expect(surface.isDestroyed()).toBe(false)
		t.expect(surface.GroupTransparency > 0).toBe(true)
		w.advance(0.1, 6)
		t.expect(surface.isDestroyed()).toBe(true)
		w.stop()
	end)
end)

t.describe("presentation motion: DisclosureGroup", function()
	local function disclosureWorld(options: any?): (any, any)
		local expanded = Compose.cell(false)
		local w = overlay.new(function(UI)
			return UI.DisclosureGroup "Settings" {
				label = "Appearance",
				expanded = expanded,
				content = function()
					return UI.Button "Palette" { label = "Palette" }
				end,
			}
		end, options)
		return w, expanded
	end

	t.it("reveals the height, fades the content and turns the chevron, frame by frame", function()
		local w, expanded = disclosureWorld()
		local caret = overlay.find(w.find("Header"), "LeadingIcon")
		t.expect(caret.Rotation).toBe(0)
		expanded:set(true)
		local reveal, fade = w.find("Reveal"), w.find("RevealFade")
		fade.AbsoluteSize = Vector2.new(300, 120)
		t.expect(reveal.ClipsDescendants).toBe(true)
		t.expect(reveal.AutomaticSize).toBe(w.Enum.AutomaticSize.None)
		t.expect(reveal.Size.Y.Offset).toBe(0)
		t.expect(fade.GroupTransparency).toBe(1)
		t.expect(caret.Rotation).toBe(-90)
		local height, rotation = 0, -90
		for _ = 1, 12 do
			w.advance(FRAME)
			t.expect(reveal.Size.Y.Offset >= height).toBe(true)
			t.expect(caret.Rotation > rotation).toBe(true)
			height, rotation = reveal.Size.Y.Offset, caret.Rotation
		end
		t.expect(height > 0 and height < 120).toBe(true)
		w.advance(0.1, 6)
		t.expect(reveal.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		t.expect(reveal.Size.Y.Offset).toBe(0)
		t.expect(fade.GroupTransparency).toBe(0)
		t.expect(caret.Rotation).toBe(0)
		w.stop()
	end)

	t.it("collapsing content leaves the selection ring at once and disposes after the motion", function()
		local w, expanded = disclosureWorld()
		expanded:set(true)
		w.advance(0.3, 18)
		local reveal, fade = w.find("Reveal"), w.find("RevealFade")
		fade.AbsoluteSize = Vector2.new(300, 120)
		local palette = w.find("Palette")
		w.gui.SelectedObject = palette
		expanded:set(false)
		t.expect(reveal.Interactable).toBe(false)
		t.expect(w.gui.SelectedObject).toBe(w.find("Header"))
		w.advance(FRAME)
		local height = reveal.Size.Y.Offset
		t.expect(height > 0 and height < 120).toBe(true)
		for _ = 1, 5 do
			w.advance(FRAME)
			t.expect(reveal.Size.Y.Offset <= height).toBe(true)
			height = reveal.Size.Y.Offset
		end
		t.expect(palette.isDestroyed()).toBe(false)
		w.advance(0.2, 12)
		t.expect(palette.isDestroyed()).toBe(true)
		t.expect(w.find("Reveal")).toBeNil()
		t.expect(w.gui.SelectedObject).toBe(w.find("Header"))
		w.stop()
	end)

	t.it("expanding again during the collapse keeps the same content", function()
		local w, expanded = disclosureWorld()
		expanded:set(true)
		w.advance(0.3, 18)
		local palette = w.find("Palette")
		expanded:set(false)
		w.advance(0.05, 3)
		expanded:set(true)
		t.expect(w.find("Palette")).toBe(palette)
		t.expect(w.find("Reveal").Interactable).toBe(true)
		w.advance(0.3, 18)
		t.expect(w.find("RevealFade").GroupTransparency).toBe(0)
		w.stop()
	end)

	t.it("reduced motion expands and collapses at once", function()
		local w, expanded = disclosureWorld({ reducedMotion = true })
		expanded:set(true)
		local reveal = w.find("Reveal")
		t.expect(reveal.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		t.expect(w.find("RevealFade").GroupTransparency).toBe(0)
		t.expect(overlay.find(w.find("Header"), "LeadingIcon").Rotation).toBe(0)
		expanded:set(false)
		t.expect(reveal.isDestroyed()).toBe(true)
		w.stop()
	end)
end)

t.describe("presentation motion: Snackbar and Notice", function()
	t.it("a snackbar row slides up and fades in, then slides down and fades out", function()
		local shown = Compose.cell(false)
		local w = overlay.new(function(UI)
			return UI.Snackbar "Saved" {
				isPresented = shown,
				message = "Saved",
				closeButton = false,
			}
		end)
		shown:set(true)
		local row = w.find("Snack")
		row.AbsoluteSize = Vector2.new(300, 48)
		t.expect(row.ClassName).toBe("CanvasGroup")
		t.expect(row.GroupTransparency).toBe(1)
		local travel, fade = row.Position.Y.Offset, row.GroupTransparency
		for _ = 1, 8 do
			w.advance(FRAME)
			t.expect(row.Position.Y.Offset < travel).toBe(true)
			t.expect(row.GroupTransparency < fade).toBe(true)
			travel, fade = row.Position.Y.Offset, row.GroupTransparency
		end
		w.advance(0.2, 12)
		t.expect(row.GroupTransparency).toBe(0)
		t.expect(row.Position.Y.Offset).toBe(-16)
		shown:set(false)
		t.expect(row.Interactable).toBe(false)
		w.advance(0.1, 6)
		t.expect(row.GroupTransparency > 0).toBe(true)
		t.expect(row.Position.Y.Offset > -16).toBe(true)
		w.advance(0.15, 9)
		t.expect(row.isDestroyed()).toBe(true)
		w.stop()
	end)

	local function noticeWorld(options: any?): (any, any, { number })
		local shown = Compose.cell(true)
		local closes: { number } = {}
		local w = overlay.new(function(UI)
			return Compose.show(shown, function()
				return UI.Notice "Offline" {
					message = "You are offline",
					onDismiss = function()
						table.insert(closes, 1)
					end,
				}
			end)
		end, options)
		return w, shown, closes
	end

	t.it("a notice unrolls its height on arrival", function()
		local w = noticeWorld()
		local notice = w.find("Offline")
		w.find("Body").AbsoluteSize = Vector2.new(300, 40)
		t.expect(notice.AutomaticSize).toBe(w.Enum.AutomaticSize.None)
		t.expect(notice.ClipsDescendants).toBe(true)
		t.expect(notice.Size.Y.Offset).toBe(0)
		local height = 0
		for _ = 1, 10 do
			w.advance(FRAME)
			t.expect(notice.Size.Y.Offset >= height).toBe(true)
			height = notice.Size.Y.Offset
		end
		t.expect(height > 0 and height < 60).toBe(true)
		w.advance(0.2, 12)
		t.expect(notice.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		t.expect(notice.Size).toBe(w.engine.types.UDim2.new(1, 0, 0, 0))
		t.expect(notice.ClipsDescendants).toBe(false)
		w.stop()
	end)

	t.it("the close collapses the notice first, then reports; a notice the caller keeps comes back", function()
		local w, shown, closes = noticeWorld()
		w.advance(0.3, 18)
		local notice = w.find("Offline")
		w.find("Body").AbsoluteSize = Vector2.new(300, 40)
		local close = overlay.find(notice, "Close")
		w.gui.SelectedObject = close
		close.Activated.fire()
		t.expect(#closes).toBe(0)
		t.expect(notice.Interactable).toBe(false)
		t.expect(w.gui.SelectedObject).toBe(nil)
		w.advance(0.1, 6)
		t.expect(notice.Size.Y.Offset > 0 and notice.Size.Y.Offset < 60).toBe(true)
		t.expect(#closes).toBe(0)
		w.advance(0.15, 9)
		t.expect(#closes).toBe(1)
		t.expect(notice.Interactable).toBe(true)
		w.advance(0.3, 18)
		t.expect(notice.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		close.Activated.fire()
		w.advance(0.25, 15)
		t.expect(#closes).toBe(2)
		shown:set(false)
		t.expect(notice.isDestroyed()).toBe(true)
		w.stop()
	end)

	t.it("reduced motion shows a notice at rest and reports the close at once", function()
		local w, _, closes = noticeWorld({ reducedMotion = true })
		local notice = w.find("Offline")
		t.expect(notice.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		w.advance(0.1, 6)
		overlay.find(notice, "Close").Activated.fire()
		t.expect(#closes).toBe(1)
		w.stop()
	end)
end)

t.describe("presentation motion: the Popover compact sheet", function()
	t.it("titles the sheet, hugs the content and slides up on a portrait phone", function()
		local open = Compose.cell(false)
		local w = overlay.new(function(UI, Host)
			return UI.Popover "Status" {
				source = { rect = { x = 300, y = 20, w = 40, h = 40 } },
				isPresented = open,
				onPresentedChange = function(value: boolean)
					open:set(value)
				end,
				title = "Status",
				content = function()
					return Host.TextLabel "Presence" { Text = "Online" }
				end,
			}
		end)
		w.input.PreferredInput = w.Enum.PreferredInput.Touch
		w.screen.AbsoluteSize = Vector2.new(390, 800)
		open:set(true)
		local panel = w.find("SheetPanel")
		t.expect(panel ~= nil).toBe(true)
		local header = overlay.find(panel, "Header")
		t.expect(overlay.find(header, "Title").Text).toBe("Status")
		t.expect(overlay.find(header, "Close") ~= nil).toBe(true)
		t.expect(overlay.find(panel, "Grabber"):GetAttribute("AccessibleLabel")).toBe("Size: Fit")
		t.expect(panel.Size.Y.Offset < 400).toBe(true)
		local modal = w.find("Modal")
		if modal then
			modal.AbsoluteSize = Vector2.new(390, 800)
		end
		w.advance(FRAME)
		w.advance(FRAME)
		local travel = panel.Position.Y.Offset
		t.expect(travel > 0).toBe(true)
		for _ = 1, 6 do
			w.advance(FRAME)
			t.expect(panel.Position.Y.Offset < travel).toBe(true)
			travel = panel.Position.Y.Offset
		end
		w.stop()
	end)

	t.it("an untitled popover still shows an empty title beside Done", function()
		local open = Compose.cell(true)
		local w = overlay.new(function(UI, Host)
			return UI.Popover "Plain" {
				source = { rect = { x = 300, y = 20, w = 40, h = 40 } },
				isPresented = open,
				onPresentedChange = function(value: boolean)
					open:set(value)
				end,
				content = function()
					return Host.TextLabel "Presence" { Text = "Online" }
				end,
			}
		end)
		w.input.PreferredInput = w.Enum.PreferredInput.Touch
		w.screen.AbsoluteSize = Vector2.new(390, 800)
		local header = overlay.find(w.find("SheetPanel"), "Header")
		t.expect(overlay.find(header, "Title").Text).toBe("")
		w.stop()
	end)
end)
