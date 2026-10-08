--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)

	local materialize = require("./lib/materialize")
	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local placement = require("../src/ui/overlay_placement")
	local Vector2 = require("@lune/roblox").Vector2
	local UDim2 = require("@lune/roblox").UDim2
	local LIFT = 16 * math.sqrt(2) / 2
	local function corner(panel: any): (number, number)
		return panel.Position.X.Offset - panel.AnchorPoint.X * panel.AbsoluteSize.X,
			panel.Position.Y.Offset - panel.AnchorPoint.Y * panel.AbsoluteSize.Y
	end
	local function near(actual: number, expected: number): boolean
		return math.abs(actual - expected) <= 1
	end

	type Log = { changes: { boolean }, dismissed: { string } }

	local function caller(accept: boolean?): (any, Log, (boolean) -> ())
		local open = Compose.cell(false)
		local log: Log = { changes = {}, dismissed = {} }
		return open,
			log,
			function(nextValue: boolean)
				table.insert(log.changes, nextValue)
				if accept ~= false then
					open:set(nextValue)
				end
			end
	end

	local function content(UI: any, Host: any): any
		return Host.Frame({
			Name = "Card",
			BackgroundTransparency = 1,
			Host.TextLabel "Line" { Text = "Popover body" } :: unknown,
			UI.Button "Inner" { label = "Inner" },
		})
	end

	local function mount(specOf: (any, any) -> any, options: any?): any
		local o = options or {}
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine, gui)
			local children = { UI.Popover "Tip"(specOf(UI, Host)), UI.Button "Other" { label = "Other" } }
			for _, extra in o.extra or {} do
				table.insert(children, extra(UI, Host))
			end
			return Host.Frame({ Name = "S", table.unpack((children :: unknown) :: { unknown }) })
		end, o)
		return w
	end

	local function standard(open: any, log: Log, change: any, extra: { [string]: any }?): (any, any) -> any
		return function(UI: FacetControls, Host: RobloxHost)
			local spec: any = {
				isPresented = open,
				onPresentedChange = change,
				onDismiss = function(reason: string)
					table.insert(log.dismissed, reason)
				end,
				trigger = UI.Button "Open" { label = "Open" },
				content = function(): Instance
					return content(UI, Host)
				end,
			}
			for key, value in (extra or {} :: { [string]: any }) do
				spec[key] = value
			end
			return spec
		end
	end

	verifyHarness:suite("native Popover: the caller's fact decides, proposals ask", function()
		verifyHarness:case("shows Close on modal panels and keeps a refused proposal visible", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::shows Close on modal panels and keeps a refused proposal visible",
			run = function()
				local open, log, change = caller(false)
				local w = mount(standard(open, log, change, { closeButton = true }))
				open:set(true)
				Verify.expect(w.find("CloseCommand").Visible):toBe(true)
				w.find("CloseCommand").Activated:Fire()
				Verify.expect(open:peek()):toBe(true)
				Verify.expect(log.changes[1]):toBe(false)
				w.stop()
			end,
		})
		verifyHarness:case("a trigger press proposes, and an accepted fact presents an anchored panel", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::a trigger press proposes, and an accepted fact presents an anchored panel",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				Verify.expect((w.find("Panel"))):toBeNil()
				w.find("Open").Activated:Fire()
				Verify.expect(#log.changes):toBe(1)
				Verify.expect(log.changes[1]):toBe(true)
				Verify.expect(overlay.find(w.find("Body"), "Line").Text):toBe("Popover body")
				Verify.expect((w.find("TipModal"):GetAttribute("FacetRoute"))):toBe("popover")
				Verify.expect(w.find("DismissOutside").BackgroundTransparency):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case(
			"a refused proposal presents nothing, and a refused close keeps the same surface and focus",
			{
				id = "native_popover::native Popover: the caller's fact decides, proposals ask::a refused proposal presents nothing, and a refused close keeps the same surface and focus",
				run = function()
					local open, log, change = caller(false)
					local w = mount(standard(open, log, change))
					w.find("Open").Activated:Fire()
					Verify.expect((w.find("Panel"))):toBeNil()
					open:set(true)
					local panel = w.find("Panel")
					Verify.expect(panel ~= nil):toBe(true)
					local inner = overlay.find(panel, "Inner")
					w.gui.SelectedObject = inner
					w.find("ModalBack").Pressed:Fire()
					w.find("DismissOutside").Activated:Fire({ Position = Vector2.new(790, 590) })
					Verify.expect((w.find("Panel"))):toBe(panel)
					Verify.expect(w.gui.SelectedObject):toBe(inner)
					Verify.expect(#log.dismissed):toBe(0)
					Verify.expect(log.changes[#log.changes]):toBe(false)
					w.stop()
				end,
			}
		)

		verifyHarness:case("an outside tap closes a popover whose full-screen popup layer covers the tap", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::an outside tap closes a popover whose full-screen popup layer covers the tap",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				open:set(true)
				local panel = w.find("Panel")
				panel.Parent.AbsoluteSize = Vector2.new(800, 600)
				w.find("DismissOutside").Parent.AbsoluteSize = Vector2.new(800, 600)
				panel.AbsolutePosition = Vector2.new(10, 10)
				panel.AbsoluteSize = Vector2.new(200, 100)
				w.find("DismissOutside").Activated:Fire({ Position = Vector2.new(100, 50) })
				Verify.expect(w.find("Panel") ~= nil):toBe(true)
				w.find("DismissOutside").Activated:Fire({ Position = Vector2.new(700, 500) })
				Verify.expect((w.find("Panel"))):toBeNil()
				Verify.expect((table.concat(log.dismissed, ","))):toBe("outside")
				w.stop()
			end,
		})

		verifyHarness:case("Cancel, an outside tap and a press on the trigger each close with their own reason, once", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::Cancel, an outside tap and a press on the trigger each close with their own reason, once",
			run = function()
				for _, case in { "cancel", "outside", "trigger" } do
					local open, log, change = caller()
					local w = mount(standard(open, log, change))
					open:set(true)
					Verify.expect(w.find("Panel") ~= nil):toBe(true)
					if case == "cancel" then
						w.find("ModalBack").Pressed:Fire()
					elseif case == "outside" then
						w.find("DismissOutside").Activated:Fire({ Position = Vector2.new(790, 590) })
					else
						w.find("Open").Activated:Fire()
						Verify.expect(w.find("Panel") ~= nil):toBe(true)
						local catcher = w.find("DismissOutside")
						local modal = catcher.Parent
						modal.AbsoluteSize = Vector2.new(800, 600)
						w.find("Popup").AbsoluteSize = Vector2.new(800, 600)
						w.find("Panel").AbsolutePosition = Vector2.new(177, 212)
						w.find("Panel").AbsoluteSize = Vector2.new(107, 76)
						catcher.Activated:Fire({ Position = Vector2.new(230, 200) })
						Verify.expect(w.find("Panel") ~= nil):toBe(true)
						catcher.Activated:Fire({ Position = Vector2.new(230, 182) })
					end
					Verify.expect(`{case}: {tostring(w.find("Panel") == nil)}`):toBe(`{case}: true`)
					Verify.expect((open:peek())):toBe(false)
					Verify.expect((table.concat(log.dismissed, ",")))
						:toBe(if case == "trigger" then "outside" else case)
					w.stop()
				end
			end,
		})

		verifyHarness:case("without onPresentedChange nothing interactive opens or closes it; the fact still does", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::without onPresentedChange nothing interactive opens or closes it; the fact still does",
			run = function()
				local open = Compose.cell(false)
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = open,
						trigger = UI.Button "Open" { label = "Open" },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
				end)
				w.find("Open").Activated:Fire()
				Verify.expect((w.find("Panel"))):toBeNil()
				open:set(true)
				Verify.expect(w.find("Panel") ~= nil):toBe(true)
				w.find("ModalBack").Pressed:Fire()
				Verify.expect(w.find("Panel") ~= nil):toBe(true)
				open:set(false)
				Verify.expect((w.find("Panel"))):toBeNil()
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Popover: every input class opens and closes it through a real route", function()
		verifyHarness:case("pointer: a click on the trigger opens it and a click outside closes it", {
			id = "native_popover::native Popover: every input class opens and closes it through a real route::pointer: a click on the trigger opens it and a click outside closes it",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
				w.find("Open").Activated:Fire()
				Verify.expect(w.find("Panel") ~= nil):toBe(true)
				w.find("DismissOutside").Activated:Fire({ Position = Vector2.new(790, 590) })
				Verify.expect((open:peek())):toBe(false)
				Verify.expect((table.concat(log.dismissed, ","))):toBe("outside")
				w.stop()
			end,
		})

		verifyHarness:case(
			"keyboard: Return on the focused trigger opens it into the content, and closing returns focus",
			{
				id = "native_popover::native Popover: every input class opens and closes it through a real route::keyboard: Return on the focused trigger opens it into the content, and closing returns focus",
				run = function()
					local open, log, change = caller()
					local w = mount(standard(open, log, change))
					local trigger = w.find("Open")
					w.gui.SelectedObject = trigger
					w.action("Activate").Pressed:Fire()
					Verify.expect((open:peek())):toBe(true)
					Verify.expect((w.gui.SelectedObject:IsDescendantOf(w.find("Body")))):toBe(true)
					open:set(false)
					Verify.expect((table.concat(log.dismissed, ","))):toBe("cancel")
					Verify.expect(w.gui.SelectedObject):toBe(trigger)
					w.stop()
				end,
			}
		)

		verifyHarness:case("gamepad: ButtonA on the focused trigger opens it, and ButtonB proposes the close", {
			id = "native_popover::native Popover: every input class opens and closes it through a real route::gamepad: ButtonA on the focused trigger opens it, and ButtonB proposes the close",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				local trigger = w.find("Open")
				w.gui.SelectedObject = trigger
				trigger.Activated:Fire()
				Verify.expect((open:peek())):toBe(true)
				Verify.expect((w.gui.SelectedObject:IsDescendantOf(w.find("Panel")))):toBe(true)
				w.find("ModalBack").Pressed:Fire()
				Verify.expect((open:peek())):toBe(false)
				Verify.expect((table.concat(log.dismissed, ","))):toBe("cancel")
				Verify.expect(w.gui.SelectedObject):toBe(trigger)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Popover: sources, anchor loss and bounds", function()
		local function sourced(open: any, log: Log, change: any, target: any): (any, any) -> any
			return function(UI: FacetControls, Host: RobloxHost)
				return {
					isPresented = open,
					onPresentedChange = change,
					onDismiss = function(reason: string)
						table.insert(log.dismissed, reason)
					end,
					source = { node = target },
					content = function(): Instance
						return content(UI, Host)
					end,
				}
			end
		end

		verifyHarness:case("a node source follows its node; removing it releases at once and reports anchorLost once", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::a node source follows its node; removing it releases at once and reports anchorLost once",
			run = function()
				local open, log, change = caller()
				local target: any
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					target = Host.Frame "Target" {}
					return sourced(open, log, change, target)(UI, Host)
				end, {
					extra = {
						function()
							return target
						end,
					},
				})
				open:set(true)
				local panel = w.find("Panel")
				Verify.expect(panel ~= nil):toBe(true)
				target.AbsolutePosition = Vector2.new(100, 100)
				target.AbsoluteSize = Vector2.new(80, 40)
				panel.AbsoluteSize = Vector2.new(200, 100)
				Verify.expect((near(select(2, corner(panel)), 148 + LIFT))):toBe(true)
				local holder = target.Parent
				target.Parent = nil
				Verify.expect((w.find("Panel"))):toBeNil()
				Verify.expect((table.concat(log.dismissed, ","))):toBe("anchorLost")
				Verify.expect((open:peek())):toBe(false)
				target.Parent = holder
				Verify.expect((w.find("Panel"))):toBeNil()
				open:set(true)
				Verify.expect(w.find("Panel") ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a caller who refuses the anchorLost proposal keeps its fact, and nothing reopens", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::a caller who refuses the anchorLost proposal keeps its fact, and nothing reopens",
			run = function()
				local open, log, change = caller(false)
				local target: any
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					target = Host.Frame "Target" {}
					return sourced(open, log, change, target)(UI, Host)
				end, {
					extra = {
						function()
							return target
						end,
					},
				})
				open:set(true)
				local holder = target.Parent
				target.Parent = nil
				target.Parent = holder
				Verify.expect((open:peek())):toBe(true)
				Verify.expect((w.find("Panel"))):toBeNil()
				Verify.expect((table.concat(log.dismissed, ","))):toBe("anchorLost")
				w.stop()
			end,
		})

		verifyHarness:case("a source that has not mounted yet waits instead of being lost", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::a source that has not mounted yet waits instead of being lost",
			run = function()
				local open = Compose.cell(true)
				local target: any
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					target = Host.Frame "Target" {}
					return {
						isPresented = open,
						source = { node = target },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
				end)
				Verify.expect((w.find("Panel"))):toBeNil()
				target.Parent = w.find("S")
				Verify.expect(w.find("Panel") ~= nil):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("a rect source never draws a tail; crossOffset and edge reach the placement", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::a rect source never draws a tail; crossOffset and edge reach the placement",
			run = function()
				local open = Compose.cell(true)
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = open,
						source = { rect = { x = 300, y = 200, w = 40, h = 40 } },
						edge = "trailing" :: "trailing",
						align = "start" :: "start",
						crossOffset = 10,
						tail = true,
						content = function(): Instance
							return content(UI, Host)
						end,
					}
				end)
				local panel = w.find("Panel")
				panel.AbsoluteSize = Vector2.new(120, 80)
				Verify.expect((w.find("Tail"))):toBeNil()
				local expected = placement.solve({
					source = { x = 300, y = 200, w = 40, h = 40 },
					size = { w = 120, h = 80 },
					safe = { x = 8, y = 8, w = 800 - 16, h = 600 - 16 },
					edge = "trailing" :: "trailing",
					align = "start" :: "start",
					gap = 8,
					crossOffset = 10,
				})
				Verify.expect(expected.x):toBe(348)
				Verify.expect(panel.Position.X.Offset):toBe(expected.x)
				Verify.expect(panel.Position.Y.Offset):toBe(210)
				w.stop()
				local tailed = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = Compose.cell(true),
						trigger = UI.Button "Open" { label = "Open" },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
				end)
				local trigger = tailed.find("Open")
				trigger.AbsolutePosition = Vector2.new(300, 100)
				trigger.AbsoluteSize = Vector2.new(100, 44)
				tailed.find("Panel").AbsoluteSize = Vector2.new(160, 80)
				local tail = tailed.find("Tail")
				Verify.expect(tail.Visible and tail.Size.X.Offset == 16 and tail:HasTag("facet-tail")):toBe(true)
				Verify.expect(tail.Position.X.Offset):toBe(350)
				Verify.expect((near(tail.Position.Y.Offset, 144 + 8 + LIFT))):toBe(true)
				Verify.expect((near(select(2, corner(tailed.find("Panel"))), 144 + 8 + LIFT))):toBe(true)
				tailed.stop()
			end,
		})

		verifyHarness:case(
			"maxWidth and maxHeight bound the whole panel inside the live safe box, and the body scrolls",
			{
				id = "native_popover::native Popover: sources, anchor loss and bounds::maxWidth and maxHeight bound the whole panel inside the live safe box, and the body scrolls",
				run = function()
					local w = mount(function(UI: FacetControls, Host: RobloxHost)
						return {
							isPresented = Compose.cell(true),
							source = { rect = { x = 100, y = 20, w = 40, h = 40 } },
							maxWidth = 220,
							maxHeight = 180,
							content = function(): Instance
								return content(UI, Host)
							end,
						}
					end)
					local body = w.find("Body")
					Verify.expect(body.ClassName):toBe("ScrollingFrame")
					Verify.expect(body.AutomaticCanvasSize):toBe(w.Enum.AutomaticSize.None)
					local limit = body:FindFirstChildWhichIsA("UISizeConstraint")
					Verify.expect(limit.MaxSize):toBe(w.Vector2.new(220 - 16, 180 - 16))
					local flow = w.find("Flow")
					flow.AbsoluteSize = Vector2.new(200, 1050)
					Verify.expect(body.CanvasSize.Y.Offset):toBe(1050)
					w.advance(0.5, 10)
					flow.AbsoluteSize = Vector2.new(200, 60)
					Verify.expect(body.Size.Y.Offset):toBe(60)
					flow.AbsoluteSize = Vector2.new(200, 1050)
					Verify.expect(body.Size.Y.Offset):toBe(180 - 16)
					Verify.expect(body.AutomaticSize):toBe(w.Enum.AutomaticSize.X)
					w.screen.AbsoluteSize = Vector2.new(150, 600)
					Verify.expect(limit.MaxSize.X):toBe(150 - 16 - 16)
					local panel = w.find("Panel")
					panel.AbsoluteSize = Vector2.new(134, 164)
					Verify.expect(panel.Position.X.Offset + 134 <= 150 - 8):toBe(true)
					w.stop()
				end,
			}
		)

		verifyHarness:case("the body is exactly as tall as its canvas while a presentation scale shrinks the panel", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::the body is exactly as tall as its canvas while a presentation scale shrinks the panel",
			run = function()
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = Compose.cell(true),
						source = { rect = { x = 100, y = 20, w = 40, h = 40 } },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
				end)
				local body, flow = w.find("Body"), w.find("Flow")
				overlay.find(body, "LayoutUnit").AbsoluteSize = Vector2.new(90, 0.9)
				flow.AbsoluteSize = Vector2.new(180, 32.4)
				flow:FindFirstChildWhichIsA("UIListLayout").AbsoluteContentSize = Vector2.new(180, 32.4)
				Verify.expect(body.CanvasSize.Y.Offset):toBe(36)
				Verify.expect(body.Size.Y.Offset):toBe(body.CanvasSize.Y.Offset)
				w.stop()
			end,
		})

		verifyHarness:case(
			"measures the content at rest before the entrance and holds that height while the panel scales",
			{
				id = "native_popover::native Popover: sources, anchor loss and bounds::measures the content at rest before the entrance and holds that height while the panel scales",
				run = function()
					local w = mount(function(UI: FacetControls, Host: RobloxHost)
						return {
							isPresented = Compose.cell(true),
							source = { rect = { x = 100, y = 20, w = 40, h = 40 } },
							content = function(): Instance
								return content(UI, Host)
							end,
						}
					end)
					local body, flow, panel = w.find("Body"), w.find("Flow"), w.find("Panel")
					local scale = materialize.of(panel)
					Verify.expect(scale.Scale):toBe(1)
					flow.AbsoluteSize = Vector2.new(180, 60)
					panel.AbsoluteSize = Vector2.new(196, 76)
					w.advance(1 / 60)
					flow.AbsoluteSize = Vector2.new(180, 96)
					panel.AbsoluteSize = Vector2.new(196, 112)
					w.advance(1 / 60)
					Verify.expect(scale.Scale):toBe(1)
					Verify.expect(body.Size.Y.Offset):toBe(96)
					w.advance(1 / 60)
					w.advance(1 / 60)
					Verify.expect(scale.Scale < 1):toBe(true)
					Verify.expect(panel.Size.X.Offset):toBe(196)
					Verify.expect(panel.Size.Y.Offset):toBe(112)
					Verify.expect(w.find("PresentationPaint").Size.X.Offset):toBe(panel.Size.X.Offset)
					Verify.expect(w.find("PresentationScale").Scale < 1):toBe(true)
					flow.AbsoluteSize = Vector2.new(180, 94)
					Verify.expect(body.Size.Y.Offset):toBe(96)
					w.advance(0.5, 10)
					Verify.expect(scale.Scale):toBe(1)
					Verify.expect(body.Size.Y.Offset):toBe(94)
					w.stop()
				end,
			}
		)

		verifyHarness:case("under reduced motion shows whole, without a fade, once the panel has rested", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::under reduced motion shows whole, without a fade, once the panel has rested",
			run = function()
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = Compose.cell(true),
						source = { rect = { x = 100, y = 20, w = 40, h = 40 } },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
				end, { motionLevel = "none" })
				local flow, panel = w.find("Flow"), w.find("Panel")
				flow.AbsoluteSize = Vector2.new(180, 60)
				w.advance(1 / 60)
				flow.AbsoluteSize = Vector2.new(180, 96)
				panel.AbsoluteSize = Vector2.new(200, 120)
				w.advance(1 / 60, 3)
				local fade = panel:FindFirstChild("FadePaint")
				Verify.expect(fade == nil or fade.Transparency.Keypoints[1].Value == 0):toBe(true)
				Verify.expect((panel:FindFirstChild("Fade"))):toBe(nil)
				w.stop()
			end,
		})

		verifyHarness:case("content that fills its width gets the standard popup width instead of collapsing", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::content that fills its width gets the standard popup width instead of collapsing",
			run = function()
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = Compose.cell(true),
						source = { rect = { x = 100, y = 20, w = 40, h = 40 } },
						content = function(): Instance
							return Host.Frame({ Name = "Wide", Size = UDim2.new(1, 0, 0, 40) })
						end,
					}
				end)
				local floor
				for _, node in w.find("Flow"):GetChildren() do
					if node.ClassName == "UISizeConstraint" then
						floor = node
					end
				end
				Verify.expect(floor.MinSize.X):toBe(360 - 16)
				w.stop()
			end,
		})

		verifyHarness:case("a source that never mounts waits without an error and warns once, naming the source", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::a source that never mounts waits without an error and warns once, naming the source",
			run = function()
				local env: any = getfenv(require("../src/ui/nav_popover"))
				local warnings: { string } = {}
				env.warn = function(...)
					local parts = {}
					for index = 1, select("#", ...) do
						table.insert(parts, tostring((select(index, ...))))
					end
					table.insert(warnings, table.concat(parts, " "))
				end
				local ok, err = pcall(function()
					local open = Compose.cell(true)
					local w = mount(function(UI: FacetControls, Host: RobloxHost)
						return {
							isPresented = open,
							source = { node = Host.Frame "Nowhere" {} },
							content = function(): Instance
								return content(UI, Host)
							end,
						}
					end)
					Verify.expect((w.find("Panel"))):toBeNil()
					open:set(false)
					open:set(true)
					Verify.expect((w.find("Panel"))):toBeNil()
					Verify.expect(#warnings):toBe(1)
					Verify.expect(string.find(warnings[1], "Nowhere", 1, true) ~= nil):toBe(true)
					w.stop()
				end)
				env.warn = nil
				if not ok then
					error(err, 0)
				end
			end,
		})
	end)

	verifyHarness:suite("native Popover: the compact sheet and the live route switch", function()
		local function compactWorld(extra: { [string]: any }?): (any, any, Log)
			local open, log, change = caller()
			local w = mount(standard(open, log, change, extra))
			w.input.PreferredInput = w.Enum.PreferredInput.Touch
			w.screen.AbsoluteSize = Vector2.new(390, 800)
			return w, open, log
		end

		verifyHarness:case("a compact touch screen presents it as a sheet; compact = popover suppresses that", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::a compact touch screen presents it as a sheet; compact = popover suppresses that",
			run = function()
				local w, open = compactWorld()
				open:set(true)
				Verify.expect(w.find("SheetPanel") ~= nil):toBe(true)
				Verify.expect((w.find("Popup"))):toBeNil()
				Verify.expect(overlay.find(w.find("SheetContent"), "Line").Text):toBe("Popover body")
				w.stop()
				local p, openP = compactWorld({ compact = "popover" })
				openP:set(true)
				Verify.expect((p.find("SheetPanel"))):toBeNil()
				Verify.expect(p.find("Popup") ~= nil):toBe(true)
				p.stop()
			end,
		})

		verifyHarness:case("a sheet dismissed by something the popover did not drive still proposes and reports", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::a sheet dismissed by something the popover did not drive still proposes and reports",
			run = function()
				local w, open, log = compactWorld()
				open:set(true)
				Verify.expect(w.find("SheetPanel") ~= nil):toBe(true)
				w.find("S").Visible = false
				Verify.expect((w.find("SheetPanel"))):toBeNil()
				Verify.expect((open:peek())):toBe(false)
				Verify.expect((table.concat(log.dismissed, ","))):toBe("cancel")
				w.stop()
			end,
		})

		verifyHarness:case("the sheet's Close asks first: refused keeps it, accepted closes with cancel", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::the sheet's Close asks first: refused keeps it, accepted closes with cancel",
			run = function()
				local open, log, change = caller(false)
				local w = mount(standard(open, log, change))
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				w.screen.AbsoluteSize = Vector2.new(390, 800)
				open:set(true)
				local panel = w.find("SheetPanel")
				w.find("Grabber").Activated:Fire()
				Verify.expect((w.find("SheetPanel"))):toBe(panel)
				Verify.expect(log.changes[#log.changes]):toBe(false)
				Verify.expect(#log.dismissed):toBe(0)
				w.stop()
				local w2, open2, log2 = compactWorld()
				open2:set(true)
				w2.find("Grabber").Activated:Fire()
				Verify.expect((w2.find("SheetPanel"))):toBeNil()
				Verify.expect((table.concat(log2.dismissed, ","))):toBe("cancel")
				w2.stop()
			end,
		})

		verifyHarness:case("keeps the first outside touch through the phone route change", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::keeps the first outside touch through the phone route change",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				w.screen.AbsoluteSize = Vector2.new(390, 800)
				open:set(true)
				local panel = w.find("Panel")
				panel.AbsolutePosition, panel.AbsoluteSize = Vector2.new(100, 100), Vector2.new(200, 150)
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				Verify.expect(w.find("SheetPanel") ~= nil):toBe(true)
				local touch = {
					UserInputType = w.Enum.UserInputType.Touch,
					UserInputState = w.Enum.UserInputState.Begin,
					Position = Vector2.new(10, 10),
				}
				w.input.InputBegan:Fire(touch)
				touch.UserInputState = w.Enum.UserInputState.End
				w.input.InputEnded:Fire(touch)
				Verify.expect(open:peek()):toBe(false)
				Verify.expect(log.dismissed[1]):toBe("outside")
				w.stop()
			end,
		})

		verifyHarness:case("a live class change switches the route silently, with one content owner", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::a live class change switches the route silently, with one content owner",
			run = function()
				local builds, live = 0, 0
				local open, log, change = caller()
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					local spec = standard(open, log, change)(UI, Host)
					spec.content = function()
						builds += 1
						live += 1
						Compose.cleanup(function()
							live -= 1
						end)
						return content(UI, Host)
					end
					return spec
				end)
				w.screen.AbsoluteSize = Vector2.new(390, 800)
				open:set(true)
				Verify.expect(w.find("Popup") ~= nil):toBe(true)
				w.gui.SelectedObject = w.find("Inner")
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				Verify.expect((w.find("Popup"))):toBeNil()
				Verify.expect(w.find("SheetPanel") ~= nil):toBe(true)
				Verify.expect(builds):toBe(2)
				Verify.expect(live):toBe(1)
				Verify.expect(#log.changes):toBe(0)
				Verify.expect(#log.dismissed):toBe(0)
				Verify.expect(w.gui.SelectedObject):toBe(w.find("Inner"))
				w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(w.find("Popup") ~= nil):toBe(true)
				Verify.expect(live):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("a refused drag on the compact sheet goes back to the accepted detent", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::a refused drag on the compact sheet goes back to the accepted detent",
			run = function()
				local open, log, change = caller(false)
				local w = mount(standard(open, log, change), { motionLevel = "none" })
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				w.screen.AbsoluteSize = Vector2.new(390, 800)
				open:set(true)
				local rest = w.find("SheetPanel").Size.Y.Offset
				local drag = w.find("UIDragDetector")
				drag.DragStart:Fire(w.Vector2.new(0, 0))
				drag.DragContinue:Fire(w.Vector2.new(0, 500))
				w.tick(0.5)
				drag.DragEnd:Fire()
				Verify.expect(log.changes[#log.changes]):toBe(false)
				Verify.expect(w.find("SheetPanel") ~= nil):toBe(true)
				Verify.expect(w.find("SheetPanel").Size.Y.Offset):toBe(rest)
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Popover: callbacks that throw or re-enter, and branch cycles", function()
		verifyHarness:case("a throwing onPresentedChange changes nothing, and a throwing onDismiss still closes once", {
			id = "native_popover::native Popover: callbacks that throw or re-enter, and branch cycles::a throwing onPresentedChange changes nothing, and a throwing onDismiss still closes once",
			run = function()
				local open = Compose.cell(true)
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = open,
						onPresentedChange = function()
							error("proposal bug")
						end,
						trigger = UI.Button "Open" { label = "Open" },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
				end)
				local ok, failure = pcall(function()
					w.find("ModalBack").Pressed:Fire()
				end)
				Verify.expect(ok):toBe(false)
				Verify.expect(string.find(tostring(failure), "proposal bug", 1, true) ~= nil):toBe(true)
				Verify.expect(w.find("Panel") ~= nil):toBe(true)
				w.stop()
				local fact, calls = Compose.cell(true), 0
				local w2 = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = fact,
						onDismiss = function()
							calls += 1
							error("dismiss bug")
						end,
						trigger = UI.Button "Open" { label = "Open" },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
				end)
				pcall(function()
					fact:set(false)
				end)
				Verify.expect((w2.find("Panel"))):toBeNil()
				Verify.expect(calls):toBe(1)
				w2.stop()
			end,
		})

		verifyHarness:case("a caller that re-opens inside its own close callback keeps one live surface", {
			id = "native_popover::native Popover: callbacks that throw or re-enter, and branch cycles::a caller that re-opens inside its own close callback keeps one live surface",
			run = function()
				local open = Compose.cell(true)
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = open,
						onPresentedChange = function(nextValue: boolean)
							open:set(nextValue)
							if not nextValue then
								open:set(true)
							end
						end,
						trigger = UI.Button "Open" { label = "Open" },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
				end)
				w.find("ModalBack").Pressed:Fire()
				Verify.expect(#w.findAll("Panel")):toBe(1)
				Verify.expect((open:peek())):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("open/close/branch cycles return the native tree to its baseline", {
			id = "native_popover::native Popover: callbacks that throw or re-enter, and branch cycles::open/close/branch cycles return the native tree to its baseline",
			run = function()
				local open, log, change = caller()
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "S",
						Compose.show(shown, function()
							return UI.Popover "Tip"(standard(open, log, change)(UI, Host))
						end),
					})
				end)
				local baseline = w.engine.census()
				for _ = 1, 3 do
					w.find("Open").Activated:Fire()
					w.find("ModalBack").Pressed:Fire()
					shown:set(false)
					shown:set(true)
				end
				local after = w.engine.census()
				Verify.expect(after.live):toBe(baseline.live)
				Verify.expect(after.connections):toBe(baseline.connections)
				Verify.expect((table.concat(log.dismissed, ","))):toBe("cancel,cancel,cancel")
				w.stop()
			end,
		})
	end)

	verifyHarness:suite("native Popover: lifetime and contract", function()
		verifyHarness:case("owner disposal releases physically and reports cancel once; two worlds stay apart", {
			id = "native_popover::native Popover: lifetime and contract::owner disposal releases physically and reports cancel once; two worlds stay apart",
			run = function()
				local open, log, change = caller()
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({
						Name = "S",
						Compose.show(shown, function()
							return UI.Popover "Tip"(standard(open, log, change)(UI, Host))
						end),
					})
				end)
				local open2, log2, change2 = caller()
				local w2 = mount(standard(open2, log2, change2))
				open:set(true)
				open2:set(true)
				shown:set(false)
				Verify.expect((w.find("Panel"))):toBeNil()
				Verify.expect((table.concat(log.dismissed, ","))):toBe("cancel")
				Verify.expect(#log.changes):toBe(0)
				Verify.expect(w2.find("Panel") ~= nil):toBe(true)
				Verify.expect(#log2.dismissed):toBe(0)
				w.stop()
				w2.stop()
			end,
		})

		verifyHarness:case("the spec is closed and the contract is refused by name", {
			id = "native_popover::native Popover: lifetime and contract::the spec is closed and the contract is refused by name",
			run = function()
				local function refuses(specOf: (any, any) -> any, fragment: string)
					local ok, failure = pcall(function()
						mount(specOf).stop()
					end)
					Verify.expect(ok):toBe(false)
					Verify.expect(`{fragment}: {string.find(tostring(failure), fragment, 1, true) ~= nil}`)
						:toBe(`{fragment}: true`)
				end
				local function base(UI: any, Host: any, extra: { [string]: any }): any
					local spec: any = {
						isPresented = Compose.cell(false),
						trigger = UI.Button "Open" { label = "Open" },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
					for key, value in extra do
						spec[key] = if value == "nil" then nil else value
					end
					return spec
				end
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(UI, Host, { isPresented = "nil" })
				end, "isPresented")
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(UI, Host, { content = "nil" })
				end, "content")
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(UI, Host, { source = { rect = { x = 0, y = 0, w = 1, h = 1 } } })
				end, "exactly one")
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(
						UI,
						Host,
						{ trigger = "nil", source = { rect = { x = 0, y = 0, w = 1, h = math.huge } } }
					)
				end, "source.rect.h")
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(UI, Host, { edge = "overlap" :: "overlap" })
				end, "edge")
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(UI, Host, { align = "middle" :: "middle" })
				end, "align")
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(UI, Host, { crossOffset = 0 / 0 })
				end, "crossOffset")
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(UI, Host, { maxWidth = -4 })
				end, "maxWidth")
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(UI, Host, { compact = "never" })
				end, "compact")
				refuses(function(UI: FacetControls, Host: RobloxHost)
					return base(UI, Host, { widht = 3 })
				end, "widht")
			end,
		})
	end)

	verifyHarness:suite(
		"native Popover: anchored chrome and the cancel policy (restored from 0.11 presentAnchored)",
		function()
			verifyHarness:case("cancelPolicy = none keeps the panel through Cancel and an outside tap", {
				id = "native_popover::native Popover: anchored chrome and the cancel policy (restored from 0.11 presentAnchored)::cancelPolicy = none keeps the panel through Cancel and an outside tap",
				run = function()
					local open, log, change = caller()
					local w = mount(standard(open, log, change, { cancelPolicy = "none" }))
					open:set(true)
					w.find("ModalBack").Pressed:Fire()
					w.find("DismissOutside").Activated:Fire({ Position = Vector2.new(790, 590) })
					Verify.expect(w.find("Panel") ~= nil):toBe(true)
					Verify.expect(#log.changes):toBe(0)
					open:set(false)
					Verify.expect((w.find("Panel"))):toBeNil()
					w.stop()
				end,
			})

			verifyHarness:case("modal = false is chrome: no catcher, no Cancel, no selection taken", {
				id = "native_popover::native Popover: anchored chrome and the cancel policy (restored from 0.11 presentAnchored)::modal = false is chrome: no catcher, no Cancel, no selection taken",
				run = function()
					local open, log, change = caller()
					local w = mount(function(UI: FacetControls, Host: RobloxHost)
						local spec = standard(open, log, change, { modal = false })(UI, Host)
						spec.trigger = nil
						spec.source = { rect = { x = 100, y = 100, w = 40, h = 40 } }
						return spec
					end)
					w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
					local other = w.find("Other")
					w.gui.SelectedObject = other
					open:set(true)
					Verify.expect(w.find("Panel") ~= nil):toBe(true)
					Verify.expect((w.find("DismissOutside"))):toBeNil()
					Verify.expect((w.find("ModalBack"))):toBeNil()
					Verify.expect(w.find("Popup").Active):toBe(false)
					Verify.expect(w.gui.SelectedObject):toBe(other)
					open:set(false)
					Verify.expect((w.find("Panel"))):toBeNil()
					w.stop()
				end,
			})

			verifyHarness:case("refuses a malformed modal or cancelPolicy by name", {
				id = "native_popover::native Popover: anchored chrome and the cancel policy (restored from 0.11 presentAnchored)::refuses a malformed modal or cancelPolicy by name",
				run = function()
					for _, extra: { modal: string?, cancelPolicy: string? } in
						{ { modal = "no" }, { cancelPolicy = "never" } } :: { { modal: string?, cancelPolicy: string? } }
					do
						local open, log, change = caller()
						local ok, failure = pcall(function()
							mount(standard(open, log, change, extra)).stop()
						end)
						Verify.expect(ok):toBe(false)
						local key = next(extra)
						Verify.expect(string.find(tostring(failure), key :: string, 1, true) ~= nil):toBe(true)
					end
				end,
			})
		end
	)

	verifyHarness:suite("app.presentAnchored", function()
		local Facet = require("../src") :: any
		local engineLib = require("./lib/native_engine")
		local function app(): (any, any)
			local engine: any = engineLib.new()
			local runtime: ComposeRuntime = Facet.Roblox.createRuntime(engine)
			local gui, input = engine.new("GuiService"), engine.new("UserInputService")
			input.GetFocusedTextBox = function()
				return nil
			end
			local target = engine.new("Folder")
			return Facet.app({
				runtime = runtime,
				types = engine.types,
				parent = target,
				services = { GuiService = gui, UserInputService = input },
				motionLevel = "none",
			} :: any),
				target
		end

		verifyHarness:case("builds a panel beside a rect in its own layer and close releases it", {
			id = "native_popover::app.presentAnchored::builds a panel beside a rect in its own layer and close releases it",
			run = function()
				local a, target = app()
				local dismissed = {}
				local close, screen = a.presentAnchored(function(UI: FacetControls)
					return UI.Text "Hint" { text = "Drag to steer" }
				end, {
					source = { rect = { x = 100, y = 100, w = 40, h = 40 } },
					modal = false,
					onDismiss = function(reason)
						table.insert(dismissed, reason)
					end,
				})
				Verify.expect(screen.Parent):toBe(target)
				Verify.expect(overlay.find(screen, "Hint").Text):toBe("Drag to steer")
				close()
				Verify.expect(screen.Parent):toBeNil()
				Verify.expect(dismissed):toEqual({ "cancel" })
				close()
				a.dispose()
			end,
		})

		verifyHarness:case("an outside tap on a modal panel dismisses it and releases the layer", {
			id = "native_popover::app.presentAnchored::an outside tap on a modal panel dismisses it and releases the layer",
			run = function()
				local a = app()
				local dismissed = {}
				local _, screen = a.presentAnchored(function(UI: FacetControls)
					return UI.Text "Hint" { text = "Tap outside" }
				end, {
					source = { rect = { x = 100, y = 100, w = 40, h = 40 } },
					onDismiss = function(reason)
						table.insert(dismissed, reason)
					end,
				})
				overlay.find(screen, "DismissOutside").Activated:Fire({ Position = Vector2.new(790, 590) })
				Verify.expect(dismissed):toEqual({ "outside" })
				Verify.expect(screen.Parent):toBeNil()
				a.dispose()
			end,
		})

		verifyHarness:case("requires a component function and a source", {
			id = "native_popover::app.presentAnchored::requires a component function and a source",
			run = function()
				local a = app()
				Verify.expect(
					(pcall(a.presentAnchored, "nope", { source = { rect = { x = 0, y = 0, w = 1, h = 1 } } }))
				)
					:toBe(false)
				Verify.expect((pcall(a.presentAnchored, function(UI: FacetControls)
					return UI.Text { text = "x" }
				end, {}))):toBe(false)
				a.dispose()
			end,
		})
	end)

	verifyHarness:suite("touch popup placement", function()
		verifyHarness:case("prefers above on touch, flips near the top edge and follows input changes", {
			id = "native_popover::touch popup placement::prefers above on touch, flips near the top edge and follows input changes",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change, { compact = "popover" }), { motionLevel = "none" })
				local anchor = w.find("Open")
				anchor.AbsolutePosition = Vector2.new(300, 250)
				anchor.AbsoluteSize = Vector2.new(80, 44)
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				open:set(true)
				local panel = w.find("Panel")
				panel.AbsoluteSize = Vector2.new(200, 100)
				Verify.expect(select(2, corner(panel)) + 100 < 250):toBe(true)
				anchor.AbsolutePosition = Vector2.new(300, 8)
				Verify.expect(select(2, corner(panel)) > 52):toBe(true)
				anchor.AbsolutePosition = Vector2.new(300, 250)
				w.input.PreferredInput = w.Enum.PreferredInput.KeyboardAndMouse
				Verify.expect(select(2, corner(panel)) > 294):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("honors an explicit edge on touch", {
			id = "native_popover::touch popup placement::honors an explicit edge on touch",
			run = function()
				local open, log, change = caller()
				local w = mount(
					standard(open, log, change, { compact = "popover", edge = "bottom" :: "bottom" }),
					{ motionLevel = "none" }
				)
				w.find("Open").AbsolutePosition = Vector2.new(300, 250)
				w.find("Open").AbsoluteSize = Vector2.new(80, 44)
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				open:set(true)
				w.find("Panel").AbsoluteSize = Vector2.new(200, 100)
				Verify.expect(select(2, corner(w.find("Panel"))) > 294):toBe(true)
				w.stop()
			end,
		})
	end)
end
