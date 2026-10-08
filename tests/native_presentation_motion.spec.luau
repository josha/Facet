--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)
	type FrameConstructor = typeof(require("@repo/tools/typecheck/aliases").FrameConstructor)
	local FixtureOverlayTypes = require("../src/ui/overlay_types")

	local materialize = require("./lib/materialize")
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
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, _, gui)
			local opener = UI.Button "Opener" { label = "About" }
			gui.SelectedObject = opener
			return Host.Frame({
				opener :: unknown,
				UI.Dialog "About" {
					isPresented = open,
					onPresentedChange = function(value: boolean)
						open:set(value)
					end,
					title = "About",
					content = function(): Instance
						return Host.TextLabel "Line" { Text = "Three apps." }
					end,
					actions = {
						{
							id = "Done",
							label = "Done",
							role = "cancel" :: "cancel",
							onActivate = function()
								open:set(false)
							end,
						} :: FixtureOverlayTypes.DialogAction,
					},
				},
			})
		end, options)
		return w, open
	end

	local function fadeOf(w: any): number
		return w.find("ScrimFade").Transparency.Keypoints[1].Value
	end

	verifyHarness:suite("presentation motion: Calendar", function()
		for _, level in { "normal", "limited", "none" } do
			verifyHarness:case(`prepares calendar layout and masks panel and scrim together in {level} motion`, {
				id = `native_presentation_motion::presentation motion: Calendar::prepares calendar layout and masks panel and scrim together in {level} motion`,
				run = function()
					local value = Compose.cell({ year = 2026, month = 10, day = 7, hour = 9, minute = 0 })
					local w = overlay.new(function(UI, Host, engine, _, _)
						return Host.Frame {
							UI.DateTimePicker "Session" {
								value = value,
								onChange = function(nextValue)
									value:set(nextValue)
								end,
								time = true,
								clock = function()
									return { year = 2026, month = 10, day = 7 }
								end,
							},
						}
					end, { motionLevel = level, size = Vector2.new(389, 762) })
					w.input.PreferredInput = w.Enum.PreferredInput.Touch
					w.find("Open").Activated:Fire()
					local surface = w.find("CalendarSurface")
					local function scrimOpacity(): number
						return (1 - w.find("DismissOutside").BackgroundTransparency) / 0.5
					end
					Verify.expect(fadeKit.of(surface)):toBe(1)
					Verify.expect(scrimOpacity()):toBe(0)
					w.size(surface, 365, 0)
					w.advance(FRAME)
					Verify.expect(fadeKit.of(surface)):toBe(1)
					w.size(surface, 365, 540)
					w.size(w.find("Calendar"), 365, 540)
					w.advance(FRAME)
					Verify.expect(fadeKit.of(surface)):toBe(1)
					w.advance(FRAME)
					local last = fadeKit.of(surface)
					local intermediate = last > 0 and last < 1
					for _ = 1, 30 do
						w.advance(FRAME)
						local alpha = fadeKit.of(surface)
						Verify.expect(alpha <= last):toBe(true)
						Verify.expect(scrimOpacity()):toBeCloseTo(1 - alpha, 1e-6)
						intermediate = intermediate or (alpha > 0 and alpha < 1)
						last = alpha
					end
					Verify.expect(last):toBe(0)
					Verify.expect(intermediate):toBe(level ~= "none")
					Verify.expect(w.find("CalendarScroll").AutomaticCanvasSize):toBe(w.Enum.AutomaticSize.Y)
					w.find("DismissOutside").Activated:Fire()
					Verify.expect(w.find("Session"):GetAttribute("presented")):toBe(false)
					w.advance(1, 60)
					Verify.expect(w.find("CalendarSurface")):toBe(nil)
					w.stop()
				end,
			})
		end
	end)

	verifyHarness:suite("presentation motion: Dialog and CollapsibleView", function()
		verifyHarness:case("keeps native surface style roles on the stationary alert group", {
			id = "native_presentation_motion::presentation motion: Dialog and CollapsibleView::keeps native surface style roles on the stationary alert group",
			run = function()
				local open = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls)
					return UI.Alert "Reset" {
						isPresented = open,
						title = "Reset look?",
						actions = { { id = "cancel", label = "Cancel" } },
					}
				end)
				open:set(true)
				local panel = w.find("AlertPanel")
				Verify.expect("panel role " .. tostring(panel:HasTag("facet-panel"))):toBe("panel role true")
				Verify.expect(panel:FindFirstChildWhichIsA("UICorner")):toBe(nil)
				w.size(panel, 357, 243)
				w.size(w.find("AlertContent").Parent, 293, 60)
				w.advance(FRAME * 3, 3)
				local parent = w.find("AlertContent").Parent
				for _ = 1, 30 do
					Verify.expect(panel:FindFirstChild("PresentationPaint", true)):toBeNil()
					Verify.expect(panel:HasTag("facet-panel")):toBe(true)
					Verify.expect(panel:HasTag("facet-alert")):toBe(true)
					Verify.expect(materialize.of(panel).Scale):toBe(1)
					Verify.expect(w.find("AlertContent").Parent):toBe(parent)
					w.advance(FRAME)
				end
				open:set(false)
				w.advance(FRAME)
				Verify.expect(panel:HasTag("facet-panel")):toBe(true)
				Verify.expect(panel:FindFirstChild("PresentationPaint", true)):toBeNil()
				w.stop()
			end,
		})

		verifyHarness:case("a dialog cross-fades in place with its scrim without changing live content geometry", {
			id = "native_presentation_motion::presentation motion: Dialog and CollapsibleView::a dialog cross-fades in place with its scrim without changing live content geometry",
			run = function()
				local w, open = dialogWorld()
				open:set(true)
				local panel = w.find("Panel")
				local scale = materialize.of(panel)
				Verify.expect(panel.ClassName):toBe("Frame")
				Verify.expect(scale.Scale):toBe(1)
				panel.AbsoluteSize = Vector2.new(560, 300)
				w.advance(FRAME)
				w.advance(FRAME)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect(fadeKit.of(panel) > 0.5):toBe(true)
				Verify.expect((fadeOf(w))):toBeCloseTo(fadeKit.of(panel), 1e-6)
				local parent = w.find("Line").Parent
				local lastFade = fadeKit.of(panel)
				for _ = 1, 11 do
					w.advance(FRAME)
					Verify.expect(scale.Scale):toBe(1)
					Verify.expect(panel:FindFirstChild("PresentationPaint", true)):toBeNil()
					Verify.expect(w.find("Line").Parent):toBe(parent)
					Verify.expect(fadeKit.of(panel) <= lastFade):toBe(true)
					Verify.expect((fadeOf(w))):toBeCloseTo(fadeKit.of(panel), 1e-6)
					lastFade = fadeKit.of(panel)
				end
				w.advance(0.05, 3)
				Verify.expect(scale.Scale):toBe(1)
				Verify.expect((fadeKit.of(panel))):toBe(0)
				Verify.expect((fadeOf(w))):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case("clears background selection while a modal prepares for pointer input", {
			id = "native_presentation_motion::presentation motion: Dialog and CollapsibleView::clears background selection while a modal prepares for pointer input",
			run = function()
				local w, open = dialogWorld()
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				w.input.GetLastInputType = function()
					return w.Enum.UserInputType.Touch
				end
				open:set(true)
				Verify.expect(w.gui.SelectedObject == nil or within(w.gui.SelectedObject, w.find("DialogModal")))
					:toBe(true)
				w.gui.SelectedObject = w.find("Opener")
				Verify.expect(w.gui.SelectedObject == nil or within(w.gui.SelectedObject, w.find("DialogModal")))
					:toBe(true)
				w.advance(0.3, 18)
				w.gui.SelectedObject = w.find("Opener")
				Verify.expect(w.gui.SelectedObject == nil or within(w.gui.SelectedObject, w.find("DialogModal")))
					:toBe(true)
				open:set(false)
				w.advance(0.3, 18)
				Verify.expect(w.gui.SelectedObject):toBe(w.find("Opener"))
				w.stop()
			end,
		})

		verifyHarness:case("updates modal focus ownership when keyboard input changes to a pointer", {
			id = "native_presentation_motion::presentation motion: Dialog and CollapsibleView::updates modal focus ownership when keyboard input changes to a pointer",
			run = function()
				local w, open = dialogWorld()
				w.input.GetLastInputType = function()
					return w.Enum.UserInputType.Keyboard
				end
				open:set(true)
				w.advance(0.3, 18)
				Verify.expect(within(w.gui.SelectedObject, w.find("DialogModal"))):toBe(true)
				w.input.LastInputTypeChanged:Fire(w.Enum.UserInputType.MouseMovement)
				w.gui.SelectedObject = w.find("Opener")
				Verify.expect(w.gui.SelectedObject):toBe(nil)
				open:set(false)
				w.advance(0.3, 18)
				Verify.expect(w.gui.SelectedObject):toBe(w.find("Opener"))
				w.stop()
			end,
		})

		verifyHarness:case(
			"a dismissed dialog reverses faster, stops taking input and hands the selection back at once",
			{
				id = "native_presentation_motion::presentation motion: Dialog and CollapsibleView::a dismissed dialog reverses faster, stops taking input and hands the selection back at once",
				run = function()
					local w, open = dialogWorld()
					open:set(true)
					w.advance(0.25, 15)
					local panel = w.find("Panel")
					Verify.expect((within(w.gui.SelectedObject, panel))):toBe(true)
					open:set(false)
					Verify.expect(w.find("DialogModal").Interactable):toBe(false)
					Verify.expect(w.gui.SelectedObject):toBe(w.find("Opener"))
					local last = fadeKit.of(panel)
					for _ = 1, 6 do
						w.advance(FRAME)
						Verify.expect(fadeKit.of(panel) >= last):toBe(true)
						last = fadeKit.of(panel)
						Verify.expect((panel:isDestroyed())):toBe(false)
					end
					Verify.expect(last):toBe(1)
					w.advance(0.06, 4)
					Verify.expect((panel:isDestroyed())):toBe(true)
					Verify.expect(w.gui.SelectedObject):toBe(w.find("Opener"))
					w.stop()
				end,
			}
		)

		verifyHarness:case("reduced motion presents a dialog whole once it has rested and dismisses it at once", {
			id = "native_presentation_motion::presentation motion: Dialog and CollapsibleView::reduced motion presents a dialog whole once it has rested and dismisses it at once",
			run = function()
				local w, open = dialogWorld({ motionLevel = "none" })
				open:set(true)
				local panel = w.find("Panel")
				panel.AbsoluteSize = Vector2.new(560, 300)
				w.advance(FRAME, 2)
				Verify.expect(materialize.of(panel).Scale):toBe(1)
				Verify.expect((fadeKit.of(panel))):toBe(0)
				w.advance(0.1, 6)
				open:set(false)
				Verify.expect((panel:isDestroyed())):toBe(true)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("CollapsibleView in place", function()
		local function tipsWorld(options: any?): (any, any)
			local expanded = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, _, gui)
				local view = UI.CollapsibleView "Tips" {
					label = "Turn step sets the increment for Rotation and both Turn buttons.",
					expanded = expanded,
					content = function(): Instance
						return UI.Button "Detail" { label = "Detail" }
					end,
				}
				gui.SelectedObject = view
				return Host.Frame({ view :: unknown, UI.Button "Other" { label = "Other" } })
			end, options)
			return w, expanded
		end

		verifyHarness:case("takes the content fade's share of the reveal from the theme's motion tokens", {
			id = "native_presentation_motion::CollapsibleView in place::takes the content fade's share of the reveal from the theme's motion tokens",
			run = function()
				local package = Facet.themes.neutralPackage()
				Verify.expect(package.metrics.motion.revealFadeShare):toBe(0.5)
				package.metrics.motion.revealFadeShare = 1
				local w, expanded = tipsWorld({ theme = package })
				expanded:set(true)
				local fade = w.find("Expanded")
				w.find("ExpandedBody").AbsoluteSize = w.Vector2.new(360, 200)
				fade.AbsoluteSize = w.Vector2.new(360, 200)
				Verify.expect((fadeKit.of(fade))):toBe(1)
				w.advance(FRAME * 2, 2)
				w.advance(0.15, 9)
				Verify.expect(fadeKit.of(fade) > 0):toBe(true)
				w.advance(0.15, 9)
				Verify.expect((fadeKit.of(fade))):toBe(0)
				w.stop()
			end,
		})

		verifyHarness:case(
			"expands from its trigger into a panel over the page, inside the safe area, without a page dim",
			{
				id = "native_presentation_motion::CollapsibleView in place::expands from its trigger into a panel over the page, inside the safe area, without a page dim",
				run = function()
					local w, expanded = tipsWorld({ motionLevel = "none" })
					local trigger = w.find("Tips")
					trigger.AbsolutePosition, trigger.AbsoluteSize = w.Vector2.new(700, 500), w.Vector2.new(120, 44)
					trigger.Activated:Fire()
					Verify.expect((expanded:peek())):toBe(true)
					local plate = w.find("Expanded")
					w.find("ExpandedBody").AbsoluteSize = w.Vector2.new(360, 200)
					Verify.expect((within(plate, trigger))):toBe(false)
					Verify.expect((within(w.find("Detail"), plate))):toBe(true)
					Verify.expect((within(w.gui.SelectedObject, plate))):toBe(true)
					Verify.expect((plate:HasTag("facet-panel"))):toBe(true)
					Verify.expect(plate.Size):toBe(w.engine.types.UDim2.fromOffset(360, 200))
					Verify.expect(plate.Position):toBe(w.engine.types.UDim2.fromOffset(800 - 8 - 360, 600 - 8 - 200))
					local backdrop = w.find("DismissOutside")
					Verify.expect(backdrop.BackgroundTransparency):toBe(1)
					Verify.expect((backdrop:HasTag("facet-scrim"))):toBe(false)
					Verify.expect(trigger:FindFirstChildWhichIsA("UICorner", true) ~= nil):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case("collapses by an outside tap, Cancel and the trigger, and hands focus back", {
			id = "native_presentation_motion::CollapsibleView in place::collapses by an outside tap, Cancel and the trigger, and hands focus back",
			run = function()
				local w, expanded = tipsWorld({ motionLevel = "none" })
				local trigger = w.find("Tips")
				trigger.Activated:Fire()
				w.find("DismissOutside").Activated:Fire()
				Verify.expect((expanded:peek())):toBe(false)
				Verify.expect((w.find("Expanded"))):toBeNil()
				Verify.expect(w.gui.SelectedObject):toBe(trigger)
				trigger.Activated:Fire()
				Verify.expect((within(w.gui.SelectedObject, w.find("Expanded")))):toBe(true)
				w.action("ModalBack").Pressed:Fire()
				Verify.expect((expanded:peek())):toBe(false)
				Verify.expect(w.gui.SelectedObject):toBe(trigger)
				trigger.Activated:Fire()
				Verify.expect((expanded:peek())):toBe(true)
				w.find("Close").Activated:Fire()
				Verify.expect((expanded:peek())):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("the plate travels at its rest size; the content fades over the first half of it", {
			id = "native_presentation_motion::CollapsibleView in place::the plate travels at its rest size; the content fades over the first half of it",
			run = function()
				local w, expanded = tipsWorld()
				local trigger = w.find("Tips")
				trigger.AbsolutePosition, trigger.AbsoluteSize = w.Vector2.new(100, 100), w.Vector2.new(120, 44)
				expanded:set(true)
				local plate, fade = w.find("Expanded"), w.find("ExpandedFade")
				w.find("ExpandedBody").AbsoluteSize = w.Vector2.new(360, 200)
				plate.AbsoluteSize = w.Vector2.new(360, 200)
				Verify.expect(plate.ClipsDescendants):toBe(true)
				Verify.expect(plate.Size):toBe(w.engine.types.UDim2.fromOffset(360, 200))
				Verify.expect((fadeKit.of(plate))):toBe(1)
				w.advance(FRAME * 2, 2)
				Verify.expect(plate.Position):toBe(w.engine.types.UDim2.fromOffset(100, 100))
				Verify.expect(plate.Size):toBe(w.engine.types.UDim2.fromOffset(360, 200))
				Verify.expect(fade.Size):toBe(w.engine.types.UDim2.fromOffset(360, 200))
				Verify.expect((fadeKit.of(plate))):toBe(1)
				w.advance(0.05, 3)
				Verify.expect(plate.Size):toBe(w.engine.types.UDim2.fromOffset(360, 200))
				Verify.expect(fadeKit.of(plate) > 0 and fadeKit.of(plate) < 1):toBe(true)
				w.advance(0.1, 6)
				Verify.expect((fadeKit.of(plate))):toBe(0)
				Verify.expect(plate.Size):toBe(w.engine.types.UDim2.fromOffset(360, 200))
				w.advance(0.15, 9)
				Verify.expect(plate.Size):toBe(w.engine.types.UDim2.fromOffset(360, 200))
				expanded:set(false)
				w.advance(0.05, 3)
				Verify.expect(fadeKit.of(plate) > 0 and fadeKit.of(plate) < 1):toBe(true)
				w.advance(0.05, 3)
				Verify.expect((plate:isDestroyed())):toBe(false)
				Verify.expect((fadeKit.of(plate))):toBe(1)
				Verify.expect(plate.Size):toBe(w.engine.types.UDim2.fromOffset(360, 200))
				w.advance(0.2, 12)
				Verify.expect((plate:isDestroyed())):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("reduced motion expands and collapses at once", {
			id = "native_presentation_motion::CollapsibleView in place::reduced motion expands and collapses at once",
			run = function()
				local w, expanded = tipsWorld({ motionLevel = "none" })
				expanded:set(true)
				local plate = w.find("Expanded")
				w.find("ExpandedBody").AbsoluteSize = w.Vector2.new(360, 200)
				plate.AbsoluteSize = w.Vector2.new(360, 200)
				Verify.expect((fadeKit.of(plate))):toBe(1)
				w.advance(FRAME * 2, 2)
				Verify.expect((fadeKit.of(plate))):toBe(0)
				expanded:set(false)
				Verify.expect((plate:isDestroyed())):toBe(true)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("presentation motion: DisclosureGroup", function()
		local function disclosureWorld(options: any?): (any, any)
			local expanded = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls)
				return UI.DisclosureGroup "Settings" {
					label = "Appearance",
					expanded = expanded,
					content = function(): Instance
						return UI.Button "Palette" { label = "Palette" }
					end,
				}
			end, options)
			return w, expanded
		end

		verifyHarness:case(
			"reveals the height, fades the content in its first half and turns the chevron, frame by frame",
			{
				id = "native_presentation_motion::presentation motion: DisclosureGroup::reveals the height, fades the content in its first half and turns the chevron, frame by frame",
				run = function()
					local w, expanded = disclosureWorld()
					local caret = overlay.find(w.find("Header"), "LeadingIcon")
					Verify.expect(caret.Rotation):toBe(0)
					expanded:set(true)
					local reveal, fade = w.find("Reveal"), w.find("RevealFade")
					fade.AbsoluteSize = Vector2.new(300, 120)
					Verify.expect(reveal.ClipsDescendants):toBe(true)
					Verify.expect(reveal.AutomaticSize):toBe(w.Enum.AutomaticSize.None)
					Verify.expect(reveal.Size.Y.Offset):toBe(0)
					Verify.expect((fadeKit.of(fade))):toBe(1)
					Verify.expect(caret.Rotation):toBe(-90)
					local height, rotation = 0, -90
					for _ = 1, 12 do
						w.advance(FRAME)
						Verify.expect(reveal.Size.Y.Offset >= height):toBe(true)
						Verify.expect(caret.Rotation > rotation):toBe(true)
						height, rotation = reveal.Size.Y.Offset, caret.Rotation
					end
					Verify.expect(height > 0 and height < 120):toBe(true)
					Verify.expect((fadeKit.of(fade))):toBe(0)
					w.advance(0.1, 6)
					Verify.expect(reveal.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
					Verify.expect(reveal.Size.Y.Offset):toBe(0)
					Verify.expect((fadeKit.of(fade))):toBe(0)
					Verify.expect(caret.Rotation):toBe(0)
					w.stop()
				end,
			}
		)

		verifyHarness:case("collapsing content leaves the selection ring at once and disposes after the motion", {
			id = "native_presentation_motion::presentation motion: DisclosureGroup::collapsing content leaves the selection ring at once and disposes after the motion",
			run = function()
				local w, expanded = disclosureWorld()
				expanded:set(true)
				w.advance(0.3, 18)
				local reveal, fade = w.find("Reveal"), w.find("RevealFade")
				fade.AbsoluteSize = Vector2.new(300, 120)
				local palette = w.find("Palette")
				w.gui.SelectedObject = palette
				expanded:set(false)
				Verify.expect(reveal.Interactable):toBe(false)
				Verify.expect(w.gui.SelectedObject):toBe(w.find("Header"))
				w.advance(FRAME)
				local height = reveal.Size.Y.Offset
				Verify.expect(height > 0 and height < 120):toBe(true)
				for _ = 1, 5 do
					w.advance(FRAME)
					Verify.expect(reveal.Size.Y.Offset <= height):toBe(true)
					height = reveal.Size.Y.Offset
				end
				Verify.expect((palette:isDestroyed())):toBe(false)
				w.advance(0.2, 12)
				Verify.expect((palette:isDestroyed())):toBe(true)
				Verify.expect((w.find("Reveal"))):toBeNil()
				Verify.expect(w.gui.SelectedObject):toBe(w.find("Header"))
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("presentation motion: Toast with an action, and Notice", function()
		verifyHarness:case("an action toast row slides up and fades in, then slides down and fades out", {
			id = "native_presentation_motion::presentation motion: Toast with an action, and Notice::an action toast row slides up and fades in, then slides down and fades out",
			run = function()
				local shown = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls)
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
				Verify.expect(row.ClassName):toBe("Frame")
				Verify.expect((fadeKit.of(row))):toBe(1)
				local travel, fade = row.Position.Y.Offset, fadeKit.of(row)
				for _ = 1, 8 do
					w.advance(FRAME)
					Verify.expect(row.Position.Y.Offset < travel):toBe(true)
					Verify.expect(fadeKit.of(row) < fade):toBe(true)
					travel, fade = row.Position.Y.Offset, fadeKit.of(row)
				end
				w.advance(0.2, 12)
				Verify.expect((fadeKit.of(row))):toBe(0)
				Verify.expect(row.Position.Y.Offset):toBe(-16)
				shown:set(false)
				Verify.expect(row.Interactable):toBe(false)
				w.advance(0.1, 6)
				Verify.expect(fadeKit.of(row) > 0):toBe(true)
				Verify.expect(row.Position.Y.Offset > -16):toBe(true)
				w.advance(0.15, 9)
				Verify.expect((row:isDestroyed())):toBe(true)
				w.stop()
			end,
		})

		local function noticeWorld(options: any?): (any, any, { number })
			local shown = Compose.cell(true)
			local closes: { number } = {}
			local w = overlay.new(function(UI: FacetControls)
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

		verifyHarness:case("a notice unrolls its height on arrival", {
			id = "native_presentation_motion::presentation motion: Toast with an action, and Notice::a notice unrolls its height on arrival",
			run = function()
				local w = noticeWorld()
				local notice = w.find("Offline")
				w.find("Body").AbsoluteSize = Vector2.new(300, 40)
				Verify.expect(notice.AutomaticSize):toBe(w.Enum.AutomaticSize.None)
				Verify.expect(notice.ClipsDescendants):toBe(true)
				Verify.expect(notice.Size.Y.Offset):toBe(0)
				local height = 0
				for _ = 1, 10 do
					w.advance(FRAME)
					Verify.expect(notice.Size.Y.Offset >= height):toBe(true)
					height = notice.Size.Y.Offset
				end
				Verify.expect(height > 0 and height < 60):toBe(true)
				w.advance(0.2, 12)
				Verify.expect(notice.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
				Verify.expect(notice.Size):toBe(w.engine.types.UDim2.new(1, 0, 0, 0))
				Verify.expect(notice.ClipsDescendants):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("the close collapses the notice first, then reports; a notice the caller keeps comes back", {
			id = "native_presentation_motion::presentation motion: Toast with an action, and Notice::the close collapses the notice first, then reports; a notice the caller keeps comes back",
			run = function()
				local w, shown, closes = noticeWorld()
				w.advance(0.3, 18)
				local notice = w.find("Offline")
				w.find("Body").AbsoluteSize = Vector2.new(300, 40)
				local close = overlay.find(notice, "Close")
				w.gui.SelectedObject = close
				close.Activated:Fire()
				Verify.expect(#closes):toBe(0)
				Verify.expect(notice.Interactable):toBe(false)
				Verify.expect(w.gui.SelectedObject):toBe(nil)
				w.advance(0.1, 6)
				Verify.expect(notice.Size.Y.Offset > 0 and notice.Size.Y.Offset < 60):toBe(true)
				Verify.expect(#closes):toBe(0)
				w.advance(0.15, 9)
				Verify.expect(#closes):toBe(1)
				Verify.expect(notice.Interactable):toBe(true)
				w.advance(0.3, 18)
				Verify.expect(notice.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
				close.Activated:Fire()
				w.advance(0.25, 15)
				Verify.expect(#closes):toBe(2)
				shown:set(false)
				Verify.expect((notice:isDestroyed())):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("at limited a notice lands its height at once and fades its content in and out", {
			id = "native_presentation_motion::presentation motion: Toast with an action, and Notice::at limited a notice lands its height at once and fades its content in and out",
			run = function()
				local w, _, closes = noticeWorld({ motionLevel = "limited" })
				local notice = w.find("Offline")
				local body = w.find("Body")
				Verify.expect(notice.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
				Verify.expect(fadeKit.of(body) > 0):toBe(true)
				w.advance(FRAME)
				Verify.expect(fadeKit.of(body) > 0 and fadeKit.of(body) < 1):toBe(true)
				w.advance(0.2, 12)
				Verify.expect((fadeKit.of(body))):toBe(0)
				overlay.find(notice, "Close").Activated:Fire()
				Verify.expect(#closes):toBe(0)
				Verify.expect(notice.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
				w.advance(FRAME)
				Verify.expect(fadeKit.of(body) > 0):toBe(true)
				w.advance(0.2, 12)
				Verify.expect(#closes):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("reduced motion shows a notice at rest and reports the close at once", {
			id = "native_presentation_motion::presentation motion: Toast with an action, and Notice::reduced motion shows a notice at rest and reports the close at once",
			run = function()
				local w, _, closes = noticeWorld({ motionLevel = "none" })
				local notice = w.find("Offline")
				Verify.expect(notice.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
				w.advance(0.1, 6)
				overlay.find(notice, "Close").Activated:Fire()
				Verify.expect(#closes):toBe(1)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("presentation motion: the Popover compact sheet", function()
		verifyHarness:case("titles the sheet, hugs the content and slides up on a portrait phone", {
			id = "native_presentation_motion::presentation motion: the Popover compact sheet::titles the sheet, hugs the content and slides up on a portrait phone",
			run = function()
				local open = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Popover "Status" {
						source = { rect = { x = 300, y = 20, w = 40, h = 40 } },
						isPresented = open,
						onPresentedChange = function(value: boolean)
							open:set(value)
						end,
						title = "Status",
						content = function(): Instance
							return Host.TextLabel "Presence" { Text = "Online" }
						end,
					}
				end)
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				w.screen.AbsoluteSize = Vector2.new(390, 800)
				open:set(true)
				local panel = w.find("SheetPanel")
				Verify.expect(panel ~= nil):toBe(true)
				local header = overlay.find(panel, "Header")
				Verify.expect(overlay.find(header, "Title").Text):toBe("Status")
				Verify.expect(overlay.find(header, "Close").Visible):toBe(true)
				Verify.expect((overlay.find(panel, "Grabber"):GetAttribute("AccessibleLabel"))):toBe("Close sheet")
				Verify.expect(panel.Size.Y.Offset < 400):toBe(true)
				local modal = w.find("Modal")
				if modal then
					modal.AbsoluteSize = Vector2.new(390, 800)
				end
				w.advance(FRAME)
				w.advance(FRAME)
				local travel = panel.Position.Y.Offset
				Verify.expect(travel > 0):toBe(true)
				for _ = 1, 6 do
					w.advance(FRAME)
					Verify.expect(panel.Position.Y.Offset < travel):toBe(true)
					travel = panel.Position.Y.Offset
				end
				w.stop()
			end,
		})

		verifyHarness:case("an untitled popover still shows an empty title beside Done", {
			id = "native_presentation_motion::presentation motion: the Popover compact sheet::an untitled popover still shows an empty title beside Done",
			run = function()
				local open = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Popover "Plain" {
						source = { rect = { x = 300, y = 20, w = 40, h = 40 } },
						isPresented = open,
						onPresentedChange = function(value: boolean)
							open:set(value)
						end,
						content = function(): Instance
							return Host.TextLabel "Presence" { Text = "Online" }
						end,
					}
				end)
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				w.screen.AbsoluteSize = Vector2.new(390, 800)
				local header = overlay.find(w.find("SheetPanel"), "Header")
				Verify.expect(overlay.find(header, "Title").Text):toBe("")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("ctx.fade group warm-up", function()
		local Roblox = require("../src/vendor/compose/roblox")
		local context = require("../src/ui/context")
		local engines = require("./lib/native_engine")
		local function world(theme: any?)
			local engine = engines.new()
			local runtime: ComposeRuntime = Roblox.createRuntime(engine)
			local ctx = context(Compose, runtime, {
				types = engine.types,
				theme = theme,
				services = { RunService = { Heartbeat = engine.heartbeat } :: any },
			})
			local amount = Compose.cell(0)
			local stop, node: any = runtime.mount(function()
				local node = ctx.fade({
					Name = "Faded",
					GroupTransparency = amount,
					((runtime.constructors.Frame :: unknown) :: FrameConstructor) "Child" {},
				})
				ctx.skin(node, "panel")
				return node
			end, engine.new("Folder"))
			return engine, runtime, amount, stop, node
		end
		verifyHarness:case("theme shadows share the panel fade through closing and reopening", {
			id = "native_presentation_motion::ctx.fade group warm-up::theme shadows share the panel fade through closing and reopening",
			run = function()
				for _, reactive in { false, true } do
					local package = Facet.themes.neutralPackage()
					assert(package.chrome).panel = { kind = "native" :: "native", shadow = { transparency = 0.3 } }
					local engine, runtime, amount, stop, node =
						world(if reactive then Compose.cell(package) else package)
					local shadow = node:FindFirstChild("ChromeShadow")
					for _, value in { 0, 0.25, 0.75, 1, 0.5, 0 } do
						amount:set(value)
						engine.heartbeat:Fire(FRAME)
						Verify.expect(shadow.Transparency):toBeCloseTo(1 - 0.7 * (1 - value), 5)
					end
					stop()
					runtime:dispose()
				end
			end,
		})

		verifyHarness:case("a fade out puts all content on the plate schedule at once", {
			id = "native_presentation_motion::ctx.fade group warm-up::a fade out puts all content on the plate schedule at once",
			run = function()
				local engine, runtime, amount, stop, node = world()
				amount:set(0.1)
				local group = node:FindFirstChild("Fade")
				Verify.expect(group ~= nil):toBe(true)
				Verify.expect(group:FindFirstChild("Child").Parent):toBe(group)
				Verify.expect(group.GroupTransparency):toBe(0.1)
				local late = engine.new("TextLabel")
				late.Parent = node
				Verify.expect(late.Parent):toBe(group)
				Verify.expect(fadeKit.of(node)):toBeCloseTo(group.GroupTransparency, 1e-6)
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(group:FindFirstChild("Child") ~= nil):toBe(true)
				stop()
				runtime:dispose()
			end,
		})
		verifyHarness:case("a fade in moves its content into the group at once and hides the first frame", {
			id = "native_presentation_motion::ctx.fade group warm-up::a fade in moves its content into the group at once and hides the first frame",
			run = function()
				local engine, runtime, amount, stop, node = world()
				amount:set(0.9)
				local group = node:FindFirstChild("Fade")
				Verify.expect(group:FindFirstChild("Child") ~= nil):toBe(true)
				Verify.expect(group.GroupTransparency):toBe(1)
				engine.heartbeat:Fire(1 / 60)
				Verify.expect(group.GroupTransparency):toBe(0.9)
				stop()
				runtime:dispose()
			end,
		})
	end)
	verifyHarness:suite("presentation motion: Menu measurement", function()
		verifyHarness:case("holds panel height through a one-frame row measurement handoff and accepts stable reflow", {
			id = "native_presentation_motion::presentation motion: Menu measurement::holds panel height through a one-frame row measurement handoff and accepts stable reflow",
			run = function()
				local w = overlay.new(function(UI, Host)
					return Host.Frame {
						UI.Menu "Commands" {
							label = "Actions",
							items = { { id = "save", label = "Save", onSelect = function() end } },
						},
					}
				end)
				w.find("Trigger").Activated:Fire()
				local panel, rows = w.find("MenuPanel"), w.find("MenuRows")
				w.size(w.find("Modal"), 800, 600)
				w.size(panel, 220, 104)
				w.size(rows, 220, 104)
				w.advance(1, 60)
				local height = panel.Size.Y.Offset
				w.size(rows, 220, 103)
				w.advance(FRAME)
				Verify.expect(panel.Size.Y.Offset):toBe(height)
				w.size(rows, 220, 104)
				w.advance(FRAME)
				Verify.expect(panel.Size.Y.Offset):toBe(height)
				w.size(rows, 220, 140)
				w.advance(FRAME)
				Verify.expect(panel.Size.Y.Offset):toBe(height)
				w.advance(FRAME)
				Verify.expect(panel.Size.Y.Offset):toBe(height + 36)
				w.stop()
			end,
		})
	end)
	verifyHarness:suite("presentation motion: disabled modal opener", function()
		verifyHarness:case("keeps a SurfaceGui menu and scrim until its sheet departure completes", {
			id = "native_presentation_motion::presentation motion: disabled modal opener::keeps a SurfaceGui menu and scrim until its sheet departure completes",
			run = function()
				local w = overlay.new(function(UI, Host)
					return Host.SurfaceGui "WorldUI" {
						UI.Menu "Commands" {
							label = "Actions",
							presentation = "sheet",
							items = { { id = "save", label = "Save", onSelect = function() end } },
						},
					}
				end)
				local layer = w.find("WorldUI")
				w.size(layer, 390, 844)
				w.find("Trigger").Activated:Fire()
				local panel, modal = w.find("MenuPanel"), w.find("Modal")
				w.size(modal, 390, 844)
				w.size(panel, 366, 140)
				w.size(w.find("MenuRows"), 350, 124)
				w.advance(1, 60)
				w.find("Commands").Interactable = false
				w.find("DismissOutside").Activated:Fire()
				Verify.expect(panel:isDestroyed()):toBe(false)
				local previous = panel.Position.Y.Offset
				w.advance(0.05, 3)
				Verify.expect(panel:isDestroyed()):toBe(false)
				Verify.expect(panel.Position.Y.Offset > previous):toBe(true)
				Verify.expect(w.find("DismissOutside").BackgroundTransparency > 0.5):toBe(true)
				w.advance(0.3, 18)
				Verify.expect(panel:isDestroyed()):toBe(true)
				w.stop()
			end,
		})
	end)
end
