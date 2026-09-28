--!strict
local t = require("./lib/testkit")
local fadeKit = require("./lib/fade")
local Facet = require("../src")
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
		t.expect(panel.ClassName).toBe("Frame")
		t.expect(scale.Scale).toBe(1)
		panel.AbsoluteSize = Vector2.new(560, 300)
		w.advance(FRAME)
		w.advance(FRAME)
		t.expect(scale.Scale >= 0.94 and scale.Scale < 1).toBe(true)
		t.expect(fadeKit.of(panel)).toBe(1)
		t.expect(fadeOf(w)).toBe(1)
		local lastScale, lastFade, clearedEarly = scale.Scale, fadeKit.of(panel), false
		for _ = 1, 11 do
			w.advance(FRAME)
			t.expect(scale.Scale > lastScale).toBe(true)
			t.expect(fadeKit.of(panel) <= lastFade).toBe(true)
			t.expect(fadeOf(w)).toBeCloseTo(fadeKit.of(panel), 1e-6)
			clearedEarly = clearedEarly or (fadeKit.of(panel) == 0 and scale.Scale < 1)
			lastScale, lastFade = scale.Scale, fadeKit.of(panel)
		end
		t.expect(clearedEarly).toBe(true)
		w.advance(0.05, 3)
		t.expect(scale.Scale).toBe(1)
		t.expect(fadeKit.of(panel)).toBe(0)
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
		local last = fadeKit.of(panel)
		for _ = 1, 6 do
			w.advance(FRAME)
			t.expect(fadeKit.of(panel) >= last).toBe(true)
			last = fadeKit.of(panel)
			t.expect(panel.isDestroyed()).toBe(false)
		end
		t.expect(last).toBe(1)
		w.advance(0.06, 4)
		t.expect(panel.isDestroyed()).toBe(true)
		t.expect(w.gui.SelectedObject).toBe(w.find("Opener"))
		w.stop()
	end)

	t.it("reduced motion presents a dialog whole once it has rested and dismisses it at once", function()
		local w, open = dialogWorld({ motionLevel = "none" })
		open:set(true)
		local panel = w.find("Panel")
		panel.AbsoluteSize = Vector2.new(560, 300)
		w.advance(FRAME, 2)
		t.expect(overlay.find(panel, "PresentationScale").Scale).toBe(1)
		t.expect(fadeKit.of(panel)).toBe(0)
		w.advance(0.1, 6)
		open:set(false)
		t.expect(panel.isDestroyed()).toBe(true)
		w.stop()
	end)
end)

t.describe("CollapsibleView in place", function()
	local function tipsWorld(options: any?): (any, any)
		local expanded = Compose.cell(false)
		local w = overlay.new(function(UI, Host, _, gui)
			local view = UI.CollapsibleView "Tips" {
				label = "Turn step sets the increment for Rotation and both Turn buttons.",
				expanded = expanded,
				content = function()
					return UI.Button "Detail" { label = "Detail" }
				end,
			}
			gui.SelectedObject = view
			return Host.Frame({ view, UI.Button "Other" { label = "Other" } })
		end, options)
		return w, expanded
	end

	t.it("takes the content fade's share of the reveal from the theme's motion tokens", function()
		local package = Facet.themes.neutralPackage()
		t.expect(package.metrics.motion.revealFadeShare).toBe(0.5)
		package.metrics.motion.revealFadeShare = 1
		local w, expanded = tipsWorld({ theme = package })
		expanded:set(true)
		local fade = w.find("ExpandedFade")
		w.advance(0.15, 9)
		t.expect(fadeKit.of(fade) > 0).toBe(true)
		w.advance(0.15, 9)
		t.expect(fadeKit.of(fade)).toBe(0)
		w.stop()
	end)

	t.it("collapsed shows a one-line clamped summary with a More chevron", function()
		local w = tipsWorld()
		local trigger = w.find("Tips")
		local title = overlay.find(trigger, "Title")
		t.expect(title.TextTruncate).toBe(w.Enum.TextTruncate.AtEnd)
		t.expect(title.TextWrapped).toBe(false)
		t.expect(title:FindFirstChildWhichIsA("UIFlexItem").FlexMode).toBe(w.Enum.UIFlexMode.Shrink)
		t.expect(overlay.find(trigger, "TrailingIcon") ~= nil).toBe(true)
		t.expect(w.find("Expanded")).toBeNil()
		w.stop()
	end)

	t.it("expands from its trigger into a panel over the page, inside the safe area, without a page dim", function()
		local w, expanded = tipsWorld({ motionLevel = "none" })
		local trigger = w.find("Tips")
		trigger.AbsolutePosition, trigger.AbsoluteSize = w.Vector2.new(700, 500), w.Vector2.new(120, 44)
		trigger.Activated.fire()
		t.expect(expanded:peek()).toBe(true)
		local plate = w.find("Expanded")
		w.find("ExpandedBody").AbsoluteSize = w.Vector2.new(360, 200)
		t.expect(within(plate, trigger)).toBe(false)
		t.expect(within(w.find("Detail"), plate)).toBe(true)
		t.expect(within(w.gui.SelectedObject, plate)).toBe(true)
		t.expect(plate:HasTag("facet-panel")).toBe(true)
		t.expect(plate.Size).toBe(w.engine.types.UDim2.fromOffset(360, 200))
		t.expect(plate.Position).toBe(w.engine.types.UDim2.fromOffset(800 - 8 - 360, 600 - 8 - 200))
		local backdrop = w.find("DismissOutside")
		t.expect(backdrop.BackgroundTransparency).toBe(1)
		t.expect(backdrop:HasTag("facet-scrim")).toBe(false)
		t.expect(trigger:FindFirstChildWhichIsA("UICorner", true) ~= nil).toBe(true)
		w.stop()
	end)

	t.it("collapses by an outside tap, Cancel and the trigger, and hands focus back", function()
		local w, expanded = tipsWorld({ motionLevel = "none" })
		local trigger = w.find("Tips")
		trigger.Activated.fire()
		w.find("DismissOutside").Activated.fire()
		t.expect(expanded:peek()).toBe(false)
		t.expect(w.find("Expanded")).toBeNil()
		t.expect(w.gui.SelectedObject).toBe(trigger)
		trigger.Activated.fire()
		t.expect(within(w.gui.SelectedObject, w.find("Expanded"))).toBe(true)
		w.action("ModalBack").Pressed.fire()
		t.expect(expanded:peek()).toBe(false)
		t.expect(w.gui.SelectedObject).toBe(trigger)
		trigger.Activated.fire()
		t.expect(expanded:peek()).toBe(true)
		w.find("Close").Activated.fire()
		t.expect(expanded:peek()).toBe(false)
		w.stop()
	end)

	t.it("the plate grows out of the trigger's rectangle; the content fades over the first half of it", function()
		local w, expanded = tipsWorld()
		local trigger = w.find("Tips")
		trigger.AbsolutePosition, trigger.AbsoluteSize = w.Vector2.new(100, 100), w.Vector2.new(120, 44)
		expanded:set(true)
		local plate, fade = w.find("Expanded"), w.find("ExpandedFade")
		w.find("ExpandedBody").AbsoluteSize = w.Vector2.new(360, 200)
		t.expect(plate.ClipsDescendants).toBe(true)
		t.expect(plate.Position).toBe(w.engine.types.UDim2.fromOffset(100, 100))
		t.expect(plate.Size).toBe(w.engine.types.UDim2.fromOffset(120, 44))
		t.expect(fade.Size).toBe(w.engine.types.UDim2.fromOffset(360, 200))
		t.expect(fadeKit.of(fade)).toBe(1)
		w.advance(0.05, 3)
		t.expect(plate.Size.X.Offset > 120 and plate.Size.X.Offset < 360).toBe(true)
		t.expect(fadeKit.of(fade) > 0 and fadeKit.of(fade) < 1).toBe(true)
		w.advance(0.1, 6)
		t.expect(fadeKit.of(fade)).toBe(0)
		t.expect(plate.Size.X.Offset > 120 and plate.Size.X.Offset < 360).toBe(true)
		w.advance(0.15, 9)
		t.expect(plate.Size).toBe(w.engine.types.UDim2.fromOffset(360, 200))
		expanded:set(false)
		w.advance(0.05, 3)
		t.expect(fadeKit.of(fade) > 0 and fadeKit.of(fade) < 1).toBe(true)
		w.advance(0.05, 3)
		t.expect(plate.isDestroyed()).toBe(false)
		t.expect(fadeKit.of(fade)).toBe(1)
		t.expect(plate.Size.X.Offset > 120 and plate.Size.X.Offset < 360).toBe(true)
		w.advance(0.2, 12)
		t.expect(plate.isDestroyed()).toBe(true)
		w.stop()
	end)

	t.it("reduced motion expands and collapses at once", function()
		local w, expanded = tipsWorld({ motionLevel = "none" })
		expanded:set(true)
		local plate = w.find("Expanded")
		t.expect(fadeKit.of(w.find("ExpandedFade"))).toBe(0)
		expanded:set(false)
		t.expect(plate.isDestroyed()).toBe(true)
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

	t.it("keeps a fade node's outline stroke painted out whenever no fade runs, from its first frame", function()
		local w = overlay.new(function(UI)
			return UI.DisclosureGroup "Settings" {
				label = "Appearance",
				expanded = Compose.cell(true),
				content = function()
					return UI.Button "Palette" { label = "Palette" }
				end,
			}
		end, { runService = true })
		local paint = w.find("RevealFade"):FindFirstChild("FadeStroke"):FindFirstChild("FadePaint")
		t.expect(paint.Transparency.Keypoints[1].Value).toBe(1)
		w.advance(FRAME)
		t.expect(paint.Transparency.Keypoints[1].Value).toBe(1)
		w.stop()
	end)

	t.it("reveals the height, fades the content in its first half and turns the chevron, frame by frame", function()
		local w, expanded = disclosureWorld()
		local caret = overlay.find(w.find("Header"), "LeadingIcon")
		t.expect(caret.Rotation).toBe(0)
		expanded:set(true)
		local reveal, fade = w.find("Reveal"), w.find("RevealFade")
		fade.AbsoluteSize = Vector2.new(300, 120)
		t.expect(reveal.ClipsDescendants).toBe(true)
		t.expect(reveal.AutomaticSize).toBe(w.Enum.AutomaticSize.None)
		t.expect(reveal.Size.Y.Offset).toBe(0)
		t.expect(fadeKit.of(fade)).toBe(1)
		t.expect(caret.Rotation).toBe(-90)
		local height, rotation = 0, -90
		for _ = 1, 12 do
			w.advance(FRAME)
			t.expect(reveal.Size.Y.Offset >= height).toBe(true)
			t.expect(caret.Rotation > rotation).toBe(true)
			height, rotation = reveal.Size.Y.Offset, caret.Rotation
		end
		t.expect(height > 0 and height < 120).toBe(true)
		t.expect(fadeKit.of(fade)).toBe(0)
		w.advance(0.1, 6)
		t.expect(reveal.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		t.expect(reveal.Size.Y.Offset).toBe(0)
		t.expect(fadeKit.of(fade)).toBe(0)
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
		t.expect(fadeKit.of(w.find("RevealFade"))).toBe(0)
		w.stop()
	end)

	t.it("reduced motion expands and collapses at once", function()
		local w, expanded = disclosureWorld({ motionLevel = "none" })
		expanded:set(true)
		local reveal = w.find("Reveal")
		t.expect(reveal.AutomaticSize).toBe(w.Enum.AutomaticSize.Y)
		t.expect(fadeKit.of(w.find("RevealFade"))).toBe(0)
		t.expect(overlay.find(w.find("Header"), "LeadingIcon").Rotation).toBe(0)
		expanded:set(false)
		t.expect(reveal.isDestroyed()).toBe(true)
		w.stop()
	end)
end)

t.describe("presentation motion: Toast with an action, and Notice", function()
	t.it("an action toast row slides up and fades in, then slides down and fades out", function()
		local shown = Compose.cell(false)
		local w = overlay.new(function(UI)
			return UI.Toast "Saved" {
				isPresented = shown,
				message = "Saved",
				action = { label = "Undo", onActivate = function() end },
				closeButton = false,
			}
		end)
		shown:set(true)
		local row = w.find("Snack")
		row.AbsoluteSize = Vector2.new(300, 48)
		t.expect(row.ClassName).toBe("Frame")
		t.expect(fadeKit.of(row)).toBe(1)
		local travel, fade = row.Position.Y.Offset, fadeKit.of(row)
		for _ = 1, 8 do
			w.advance(FRAME)
			t.expect(row.Position.Y.Offset < travel).toBe(true)
			t.expect(fadeKit.of(row) < fade).toBe(true)
			travel, fade = row.Position.Y.Offset, fadeKit.of(row)
		end
		w.advance(0.2, 12)
		t.expect(fadeKit.of(row)).toBe(0)
		t.expect(row.Position.Y.Offset).toBe(-16)
		shown:set(false)
		t.expect(row.Interactable).toBe(false)
		w.advance(0.1, 6)
		t.expect(fadeKit.of(row) > 0).toBe(true)
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
		local w, _, closes = noticeWorld({ motionLevel = "none" })
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
		t.expect(overlay.find(header, "Close")).toBeNil()
		t.expect(overlay.find(panel, "Grabber"):GetAttribute("AccessibleLabel")).toBe("Close sheet")
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

t.describe("ctx.fade group warm-up", function()
	local Roblox = require("../src/vendor/compose/roblox")
	local context = require("../src/ui/context")
	local engines = require("./lib/native_engine")
	local function world()
		local engine = engines.new()
		local runtime = Roblox.createRuntime(engine)
		local ctx = context(Compose, runtime, {
			types = engine.types,
			services = { RunService = { Heartbeat = engine.heartbeat } },
		})
		local amount = Compose.cell(0)
		local stop, node = runtime.mount(function()
			return ctx.fade({ Name = "Faded", GroupTransparency = amount, runtime.constructors.Frame "Child" {} })
		end, engine.new("Folder"))
		return engine, runtime, amount, stop, node
	end
	t.it("a fade out keeps its content drawn while the new group warms, then fades it in the group", function()
		local engine, runtime, amount, stop, node = world()
		amount:set(0.1)
		local group = node:FindFirstChild("Fade")
		t.expect(group ~= nil).toBe(true)
		t.expect(node:FindFirstChild("Child").Parent).toBe(node)
		t.expect(group.GroupTransparency).toBe(0.1)
		engine.heartbeat.fire(1 / 60)
		t.expect(group:FindFirstChild("Child") ~= nil).toBe(true)
		stop()
		runtime:dispose()
	end)
	t.it("a fade in moves its content into the group at once and hides the first frame", function()
		local engine, runtime, amount, stop, node = world()
		amount:set(0.9)
		local group = node:FindFirstChild("Fade")
		t.expect(group:FindFirstChild("Child") ~= nil).toBe(true)
		t.expect(group.GroupTransparency).toBe(0.99)
		engine.heartbeat.fire(1 / 60)
		t.expect(group.GroupTransparency).toBe(0.9)
		stop()
		runtime:dispose()
	end)
end)
