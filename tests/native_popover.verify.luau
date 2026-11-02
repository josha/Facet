--!strict
local FixtureRoblox = require("../tools/vendor/verify/src/roblox")
local Shared = require("../src/ui/types")
local OverlayProps = require("../src/ui/overlay_props")
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ComposeRuntime = typeof(require("@repo/tools/typecheck/aliases").ComposeRuntime)

	local materialize = require("./lib/materialize")
	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local placement = require("../src/ui/overlay_placement")
	local Vector2 = require("./lib/native_engine").types.Vector2
	local LIFT = 16 * math.sqrt(2) / 2
	local function corner(panel: any): (number, number)
		return panel.Position.X.Offset - panel.AnchorPoint.X * panel.AbsoluteSize.X,
			panel.Position.Y.Offset - panel.AnchorPoint.Y * panel.AbsoluteSize.Y
	end
	local function near(actual: number, expected: number): boolean
		return math.abs(actual - expected) <= 1
	end

	type Log = { changes: { boolean }, dismissed: { string } }

	local function caller(accept: boolean?): (Compose.Value<boolean>, Log, (boolean) -> ())
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

	local function content(UI: FacetControls, Host: RobloxHost): Frame
		return Host.Frame {
			Name = "Card",
			BackgroundTransparency = 1,
			Host.TextLabel "Line" { Text = "Popover body" },
			UI.Button "Inner" { label = "Inner" },
		}
	end

	type Builder = (FacetControls, RobloxHost) -> OverlayProps.PopoverSpec
	type MountOptions = Shared.Config & { extra: { (FacetControls, RobloxHost) -> Compose.Child }? }
	local function mount(specOf: Builder, options: MountOptions?): any
		local o: MountOptions = options or {}
		local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine, gui)
			local children: { Compose.Child } =
				{ UI.Popover(specOf(UI, Host), "Tip"), UI.Button "Other" { label = "Other" } }
			for _, extra in o.extra or {} do
				local child: Compose.Child = extra(UI, Host)
				children[#children + 1] = child
			end
			return Host.Frame { Name = "S", table.unpack(children) }
		end, o)
		return w
	end

	local function standard(open: Compose.Input<boolean>, log: Log, change: (boolean) -> (), extra: unknown?): Builder
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
			local fields = extra or {}
			assert(type(fields) == "table")
			for key, value in fields do
				spec[key] = value
			end
			return spec
		end
	end

	describe("native Popover: the caller's fact decides, proposals ask", function()
		it("shows Close on modal panels and keeps a refused proposal visible", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::shows Close on modal panels and keeps a refused proposal visible",
			run = function()
				local open, log, change = caller(false)
				local w = mount(standard(open, log, change, { closeButton = true }))
				open:set(true)
				local close = w.find("CloseCommand")
				expect(close.Visible):toBe(true)
				expect(close.Size.X.Scale):toBe(0)
				expect(close.Size.X.Offset):toBe(close.Size.Y.Offset)
				expect(close:HasTag("facet-appearance-utility")):toBe(true)
				expect(w.find("Panel"):FindFirstChildWhichIsA("UICorner")):toBe(nil)
				close.Activated:Fire()
				expect(open:peek()):toBe(true)
				expect(log.changes[1]):toBe(false)
				w.stop()
			end,
		})
		it("an anchored panel shows its title as a heading in the row with Close, above the content", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::an anchored panel shows its title as a heading in the row with Close, above the content",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change, { closeButton = true, title = "Driving options" }))
				open:set(true)
				local header = w.find("CloseHeader")
				local title = header:FindFirstChild("Title")
				local close = header:FindFirstChild("CloseCommand")
				expect(title.Text):toBe("Driving options")
				expect(title:HasTag("facet-type-heading")):toBe(true)
				expect(close ~= nil):toBe(true)
				expect(title.LayoutOrder < close.LayoutOrder):toBe(true)
				expect(header.LayoutOrder < w.find("Card").LayoutOrder):toBe(true)
				w.stop()
				local open2, log2, change2 = caller()
				local w2 = mount(standard(open2, log2, change2, { modal = false, title = "Hint" }))
				open2:set(true)
				local header2 = w2.find("CloseHeader")
				expect(header2:FindFirstChild("Title").Text):toBe("Hint")
				expect(header2:FindFirstChild("CloseCommand")):toBe(nil)
				w2.stop()
			end,
		})
		it("a trigger press proposes, and an accepted fact presents an anchored panel", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::a trigger press proposes, and an accepted fact presents an anchored panel",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				expect((w.find("Panel"))):toBeNil()
				w.find("Open").Activated:Fire()
				expect(#log.changes):toBe(1)
				expect(log.changes[1]):toBe(true)
				expect(overlay.find(w.find("Body"), "Line").Text):toBe("Popover body")
				expect((w.find("TipModal"):GetAttribute("FacetRoute"))):toBe("popover")
				expect(w.find("Scrim").BackgroundTransparency):toBe(1)
				w.stop()
			end,
		})

		it("a refused proposal presents nothing, and a refused close keeps the same surface and focus", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::a refused proposal presents nothing, and a refused close keeps the same surface and focus",
			run = function()
				local open, log, change = caller(false)
				local w = mount(standard(open, log, change))
				w.find("Open").Activated:Fire()
				expect((w.find("Panel"))):toBeNil()
				open:set(true)
				local panel = w.find("Panel")
				expect(panel ~= nil):toBe(true)
				local inner = overlay.find(panel, "Inner")
				w.gui.SelectedObject = inner
				w.find("ModalBack").Pressed:Fire()
				w.find("DismissTarget").Activated:Fire({ Position = Vector2.new(790, 590) })
				expect((w.find("Panel"))):toBe(panel)
				expect(w.gui.SelectedObject):toBe(inner)
				expect(#log.dismissed):toBe(0)
				expect(log.changes[#log.changes]):toBe(false)
				w.stop()
			end,
		})

		it("an outside tap closes a popover whose full-screen popup layer covers the tap", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::an outside tap closes a popover whose full-screen popup layer covers the tap",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				open:set(true)
				local panel = w.find("Panel")
				w.engine.environment.poke(panel.Parent, "AbsoluteSize", Vector2.new(800, 600))
				w.engine.environment.poke(w.find("Scrim").Parent, "AbsoluteSize", Vector2.new(800, 600))
				w.engine.environment.poke(panel, "AbsolutePosition", Vector2.new(10, 10))
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(200, 100))
				local outline = w.find("OutlineFade")
				w.engine.environment.poke(outline, "AbsolutePosition", Vector2.new(0, 0))
				w.engine.environment.poke(outline, "AbsoluteSize", Vector2.new(800, 600))
				w.find("DismissTarget").Activated:Fire({ Position = Vector2.new(100, 50) })
				expect(w.find("Panel") ~= nil):toBe(true)
				w.find("DismissTarget").Activated:Fire({ Position = Vector2.new(700, 500) })
				expect((w.find("Panel"))):toBeNil()
				expect((table.concat(log.dismissed, ","))):toBe("outside")
				w.stop()
			end,
		})

		it("Cancel, an outside tap and a press on the trigger each close with their own reason, once", {
			id = "native_popover::native Popover: the caller's fact decides, proposals ask::Cancel, an outside tap and a press on the trigger each close with their own reason, once",
			run = function()
				for _, case in { "cancel", "outside", "trigger" } do
					local open, log, change = caller()
					local w = mount(standard(open, log, change))
					open:set(true)
					expect(w.find("Panel") ~= nil):toBe(true)
					if case == "cancel" then
						w.find("ModalBack").Pressed:Fire()
					elseif case == "outside" then
						w.find("DismissTarget").Activated:Fire({ Position = Vector2.new(790, 590) })
					else
						w.find("Open").Activated:Fire()
						expect(w.find("Panel") ~= nil):toBe(true)
						local catcher = w.find("DismissTarget")
						local modal = catcher.Parent
						w.engine.environment.poke(modal, "AbsoluteSize", Vector2.new(800, 600))
						w.engine.environment.poke(w.find("Popup"), "AbsoluteSize", Vector2.new(800, 600))
						w.engine.environment.poke(w.find("Panel"), "AbsolutePosition", Vector2.new(177, 212))
						w.engine.environment.poke(w.find("Panel"), "AbsoluteSize", Vector2.new(107, 76))
						catcher.Activated:Fire({ Position = Vector2.new(230, 200) })
						expect(w.find("Panel") ~= nil):toBe(true)
						catcher.Activated:Fire({ Position = Vector2.new(230, 182) })
					end
					expect(`{case}: {tostring(w.find("Panel") == nil)}`):toBe(`{case}: true`)
					expect((open:peek())):toBe(false)
					expect((table.concat(log.dismissed, ","))):toBe(if case == "trigger" then "outside" else case)
					w.stop()
				end
			end,
		})

		it("without onPresentedChange nothing interactive opens or closes it; the fact still does", {
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
				expect((w.find("Panel"))):toBeNil()
				open:set(true)
				expect(w.find("Panel") ~= nil):toBe(true)
				w.find("ModalBack").Pressed:Fire()
				expect(w.find("Panel") ~= nil):toBe(true)
				open:set(false)
				expect((w.find("Panel"))):toBeNil()
				w.stop()
			end,
		})
	end)

	describe("native Popover: every input class opens and closes it through a real route", function()
		it("pointer: a click on the trigger opens it and a click outside closes it", {
			id = "native_popover::native Popover: every input class opens and closes it through a real route::pointer: a click on the trigger opens it and a click outside closes it",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.KeyboardAndMouse)
				w.find("Open").Activated:Fire()
				expect(w.find("Panel") ~= nil):toBe(true)
				w.find("DismissTarget").Activated:Fire({ Position = Vector2.new(790, 590) })
				expect((open:peek())):toBe(false)
				expect((table.concat(log.dismissed, ","))):toBe("outside")
				w.stop()
			end,
		})

		it("keyboard: Return on the focused trigger opens it into the content, and closing returns focus", {
			id = "native_popover::native Popover: every input class opens and closes it through a real route::keyboard: Return on the focused trigger opens it into the content, and closing returns focus",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				local trigger = w.find("Open")
				w.input.GetLastInputType = function()
					return w.Enum.UserInputType.Keyboard
				end
				w.gui.SelectedObject = trigger
				w.action("Activate").Pressed:Fire()
				expect((open:peek())):toBe(true)
				expect((w.gui.SelectedObject:IsDescendantOf(w.find("Body")))):toBe(true)
				open:set(false)
				expect((table.concat(log.dismissed, ","))):toBe("cancel")
				expect(w.gui.SelectedObject):toBe(trigger)
				w.stop()
			end,
		})

		it("gamepad: ButtonA on the focused trigger opens it, and ButtonB proposes the close", {
			id = "native_popover::native Popover: every input class opens and closes it through a real route::gamepad: ButtonA on the focused trigger opens it, and ButtonB proposes the close",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				local trigger = w.find("Open")
				w.gui.SelectedObject = trigger
				trigger.Activated:Fire()
				expect((open:peek())):toBe(true)
				expect((w.gui.SelectedObject:IsDescendantOf(w.find("Panel")))):toBe(true)
				w.find("ModalBack").Pressed:Fire()
				expect((open:peek())):toBe(false)
				expect((table.concat(log.dismissed, ","))):toBe("cancel")
				expect(w.gui.SelectedObject):toBe(trigger)
				w.stop()
			end,
		})
	end)

	describe("native Popover: sources, anchor loss and bounds", function()
		local function sourced(
			open: Compose.Input<boolean>,
			log: Log,
			change: (boolean) -> (),
			target: GuiObject
		): Builder
			return function(UI: FacetControls, Host: RobloxHost)
				local spec: OverlayProps.PopoverSpec = {
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
				return spec
			end
		end

		it("a node source follows its node; removing it releases at once and reports anchorLost once", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::a node source follows its node; removing it releases at once and reports anchorLost once",
			run = function()
				local open, log, change = caller()
				local target: GuiObject
				local build: Builder = function(UI: FacetControls, Host: RobloxHost)
					target = Host.Frame "Target" {}
					local specOf = sourced(open, log, change, target)
					return specOf(UI, Host)
				end
				local options: MountOptions = {
					extra = {
						function(): Instance
							return target
						end,
					},
				}
				local w = mount(build, options)
				open:set(true)
				local panel = w.find("Panel")
				expect(panel ~= nil):toBe(true)
				w.engine.environment.poke(target, "AbsolutePosition", Vector2.new(100, 100))
				w.engine.environment.poke(target, "AbsoluteSize", Vector2.new(80, 40))
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(200, 100))
				expect((near(select(2, corner(panel)), 148 + LIFT))):toBe(true)
				local holder = target.Parent
				target.Parent = nil
				expect((w.find("Panel"))):toBeNil()
				expect((table.concat(log.dismissed, ","))):toBe("anchorLost")
				expect((open:peek())):toBe(false)
				target.Parent = holder
				expect((w.find("Panel"))):toBeNil()
				open:set(true)
				expect(w.find("Panel") ~= nil):toBe(true)
				w.stop()
			end,
		})

		it("a rect source never draws a tail; crossOffset and edge reach the placement", {
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
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(120, 80))
				expect((w.find("Tail"))):toBeNil()
				local expected = placement.solve({
					source = { x = 300, y = 200, w = 40, h = 40 },
					size = { w = 120, h = 80 },
					safe = { x = 8, y = 8, w = 800 - 16, h = 600 - 16 },
					edge = "trailing" :: "trailing",
					align = "start" :: "start",
					gap = 8,
					crossOffset = 10,
				})
				expect(expected.x):toBe(348)
				expect(panel.Position.X.Offset):toBe(expected.x)
				expect(panel.Position.Y.Offset):toBe(210)
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
				tailed.engine.environment.poke(trigger, "AbsolutePosition", Vector2.new(300, 100))
				tailed.engine.environment.poke(trigger, "AbsoluteSize", Vector2.new(100, 44))
				tailed.engine.environment.poke(tailed.find("Panel"), "AbsoluteSize", Vector2.new(160, 80))
				local tail = tailed.find("Tail")
				expect(tail.Visible and tail.Size.X.Offset == 16 and tail:HasTag("facet-tail")):toBe(true)
				expect(tail.Position.X.Offset):toBe(350)
				expect((near(tail.Position.Y.Offset, 144 + 8 + LIFT))):toBe(true)
				expect((near(select(2, corner(tailed.find("Panel"))), 144 + 8 + LIFT))):toBe(true)
				tailed.stop()
			end,
		})

		it("maxWidth and maxHeight bound the whole panel inside the live safe box, and the body scrolls", {
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
				expect(body.ClassName):toBe("ScrollingFrame")
				expect(body.AutomaticCanvasSize):toBe(w.Enum.AutomaticSize.None)
				local limit = body:FindFirstChildWhichIsA("UISizeConstraint")
				expect(limit.MaxSize):toBe(w.Vector2.new(220 - 16, 180 - 16))
				local flow = w.find("Flow")
				w.engine.environment.poke(flow, "AbsoluteSize", Vector2.new(200, 1050))
				expect(body.CanvasSize.Y.Offset):toBe(1050)
				w.advance(0.5, 10)
				w.engine.environment.poke(flow, "AbsoluteSize", Vector2.new(200, 60))
				expect(body.Size.Y.Offset):toBe(60)
				w.engine.environment.poke(flow, "AbsoluteSize", Vector2.new(200, 1050))
				expect(body.Size.Y.Offset):toBe(180 - 16)
				expect(body.AutomaticSize):toBe(w.Enum.AutomaticSize.X)
				w.engine.environment.poke(w.screen, "AbsoluteSize", Vector2.new(150, 600))
				expect(limit.MaxSize.X):toBe(150 - 16 - 16)
				local panel = w.find("Panel")
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(134, 164))
				expect(panel.Position.X.Offset + 134 <= 150 - 8):toBe(true)
				w.stop()
			end,
		})

		it("the body is exactly as tall as its canvas while a presentation scale shrinks the panel", {
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
				w.engine.environment.poke(overlay.find(body, "LayoutUnit"), "AbsoluteSize", Vector2.new(90, 0.9))
				w.engine.environment.poke(flow, "AbsoluteSize", Vector2.new(180, 32.4))
				w.engine.environment.poke(
					flow:FindFirstChildWhichIsA("UIListLayout"),
					"AbsoluteContentSize",
					Vector2.new(180, 32.4)
				)
				expect(body.CanvasSize.Y.Offset):toBe(36)
				expect(body.Size.Y.Offset):toBe(body.CanvasSize.Y.Offset)
				w.stop()
			end,
		})

		it("measures the content at rest before the entrance and holds that height while the panel fades", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::measures the content at rest before the entrance and holds that height while the panel fades",
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
				expect(scale.Scale):toBe(1)
				w.engine.environment.poke(flow, "AbsoluteSize", Vector2.new(180, 60))
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(196, 76))
				w.advance(1 / 60)
				w.engine.environment.poke(flow, "AbsoluteSize", Vector2.new(180, 96))
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(196, 112))
				w.advance(1 / 60)
				expect(scale.Scale):toBe(1)
				expect(body.Size.Y.Offset):toBe(96)
				w.advance(1 / 60)
				w.advance(1 / 60)
				expect(scale.Scale):toBe(1)
				expect(panel.AbsoluteSize):toBe(Vector2.new(196, 112))
				expect(panel.AutomaticSize):toBe(w.Enum.AutomaticSize.XY)
				expect(w.find("PresentationPaint")):toBeNil()
				expect(w.find("PresentationScale")):toBeNil()
				w.engine.environment.poke(flow, "AbsoluteSize", Vector2.new(180, 94))
				expect(body.Size.Y.Offset):toBe(96)
				w.advance(0.5, 10)
				expect(scale.Scale):toBe(1)
				expect(body.Size.Y.Offset):toBe(94)
				w.stop()
			end,
		})

		it("under reduced motion shows whole, without a fade, once the panel has rested", {
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
				w.engine.environment.poke(flow, "AbsoluteSize", Vector2.new(180, 60))
				w.advance(1 / 60)
				w.engine.environment.poke(flow, "AbsoluteSize", Vector2.new(180, 96))
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(200, 120))
				w.advance(1 / 60, 3)
				local fade = panel:FindFirstChild("FadePaint")
				expect(fade == nil or fade.Transparency.Keypoints[1].Value == 0):toBe(true)
				expect(panel:FindFirstChild("Fade")):toBeNil()
				w.stop()
			end,
		})

		it("a source that never mounts waits without an error and warns once, naming the source", {
			id = "native_popover::native Popover: sources, anchor loss and bounds::a source that never mounts waits without an error and warns once, naming the source",
			run = function()
				local function environmentOf(module: unknown): { [string]: unknown }
					assert(type(module) == "function")
					return getfenv(module)
				end
				local env = environmentOf(require("../src/ui/nav_popover"))
				local warnings: { string } = {}
				env.warn = function(...)
					local parts: { string } = {}
					for index = 1, select("#", ...) do
						table.insert(parts, tostring((select(index, ...))))
					end
					table.insert(warnings, table.concat(parts, " "))
				end
				local ok, err = pcall(function()
					local open = Compose.cell(true)
					local w = mount(function(UI: FacetControls, Host: RobloxHost)
						local nowhere: GuiObject = Host.Frame "Nowhere" {}
						return {
							isPresented = open,
							source = { node = nowhere },
							content = function(): Instance
								return content(UI, Host)
							end,
						}
					end)
					expect((w.find("Panel"))):toBeNil()
					open:set(false)
					open:set(true)
					expect((w.find("Panel"))):toBeNil()
					expect(#warnings):toBe(1)
					expect(string.find(warnings[1], "Nowhere", 1, true) ~= nil):toBe(true)
					w.stop()
				end)
				env.warn = nil
				if not ok then
					error(err, 0)
				end
			end,
		})
	end)

	describe("native Popover: the compact sheet and the live route switch", function()
		local function compactWorld(extra: { [string]: any }?): (any, any, Log)
			local open, log, change = caller()
			local w = mount(standard(open, log, change, extra))
			w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
			w.engine.environment.poke(w.screen, "AbsoluteSize", Vector2.new(390, 800))
			return w, open, log
		end

		it("a compact touch screen presents it as a sheet; compact = popover suppresses that", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::a compact touch screen presents it as a sheet; compact = popover suppresses that",
			run = function()
				local w, open = compactWorld()
				open:set(true)
				expect(w.find("SheetPanel") ~= nil):toBe(true)
				expect((w.find("Popup"))):toBeNil()
				expect(overlay.find(w.find("SheetContent"), "Line").Text):toBe("Popover body")
				w.stop()
				local p, openP = compactWorld({ compact = "popover" })
				openP:set(true)
				expect((p.find("SheetPanel"))):toBeNil()
				expect(p.find("Popup") ~= nil):toBe(true)
				p.stop()
			end,
		})

		it("the sheet's Close asks first: refused keeps it, accepted closes with cancel", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::the sheet's Close asks first: refused keeps it, accepted closes with cancel",
			run = function()
				local open, log, change = caller(false)
				local w = mount(standard(open, log, change))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				w.engine.environment.poke(w.screen, "AbsoluteSize", Vector2.new(390, 800))
				open:set(true)
				local panel = w.find("SheetPanel")
				w.find("Grabber").Activated:Fire()
				expect((w.find("SheetPanel"))):toBe(panel)
				expect(log.changes[#log.changes]):toBe(false)
				expect(#log.dismissed):toBe(0)
				w.stop()
				local w2, open2, log2 = compactWorld()
				open2:set(true)
				w2.find("Grabber").Activated:Fire()
				expect((w2.find("SheetPanel"))):toBeNil()
				expect((table.concat(log2.dismissed, ","))):toBe("cancel")
				w2.stop()
			end,
		})

		it("keeps the first outside touch through the phone route change", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::keeps the first outside touch through the phone route change",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change))
				w.engine.environment.poke(w.screen, "AbsoluteSize", Vector2.new(390, 800))
				open:set(true)
				local panel = w.find("Panel")
				w.engine.environment.poke(
					FixtureRoblox.assertInstance(panel),
					"AbsolutePosition",
					Vector2.new(100, 100)
				)
				w.engine.environment.poke(FixtureRoblox.assertInstance(panel), "AbsoluteSize", Vector2.new(200, 150))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				expect(w.find("SheetPanel") ~= nil):toBe(true)
				local touch = {
					UserInputType = w.Enum.UserInputType.Touch,
					UserInputState = w.Enum.UserInputState.Begin,
					Position = Vector2.new(10, 10),
				}
				w.input.InputBegan:Fire(touch)
				touch.UserInputState = w.Enum.UserInputState.End
				w.input.InputEnded:Fire(touch)
				expect(open:peek()):toBe(false)
				expect(log.dismissed[1]):toBe("outside")
				w.stop()
			end,
		})

		it("a live class change switches the route silently, with one content owner", {
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
				w.engine.environment.poke(w.screen, "AbsoluteSize", Vector2.new(390, 800))
				open:set(true)
				expect(w.find("Popup") ~= nil):toBe(true)
				w.gui.SelectedObject = w.find("Inner")
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				expect((w.find("Popup"))):toBeNil()
				expect(w.find("SheetPanel") ~= nil):toBe(true)
				expect(builds):toBe(2)
				expect(live):toBe(1)
				expect(#log.changes):toBe(0)
				expect(#log.dismissed):toBe(0)
				expect(w.gui.SelectedObject):toBeNil()
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.KeyboardAndMouse)
				expect(w.find("Popup") ~= nil):toBe(true)
				expect(live):toBe(1)
				w.stop()
			end,
		})

		it("a refused drag on the compact sheet goes back to the accepted detent", {
			id = "native_popover::native Popover: the compact sheet and the live route switch::a refused drag on the compact sheet goes back to the accepted detent",
			run = function()
				local open, log, change = caller(false)
				local w = mount(standard(open, log, change), { motionLevel = "none" })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				w.engine.environment.poke(w.screen, "AbsoluteSize", Vector2.new(390, 800))
				open:set(true)
				local rest = w.find("SheetPanel").Size.Y.Offset
				local drag = w.find("UIDragDetector")
				drag.DragStart:Fire(w.Vector2.new(0, 0))
				drag.DragContinue:Fire(w.Vector2.new(0, 500))
				w.tick(0.5)
				drag.DragEnd:Fire()
				expect(log.changes[#log.changes]):toBe(false)
				expect(w.find("SheetPanel") ~= nil):toBe(true)
				expect(w.find("SheetPanel").Size.Y.Offset):toBe(rest)
				w.stop()
			end,
		})
	end)

	describe("native Popover: callbacks that throw or re-enter, and branch cycles", function()
		it("a throwing onPresentedChange changes nothing, and a throwing onDismiss still closes once", {
			id = "native_popover::native Popover: callbacks that throw or re-enter, and branch cycles::a throwing onPresentedChange changes nothing, and a throwing onDismiss still closes once",
			run = function()
				local open = Compose.cell(true)
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = open,
						onPresentedChange = function(): ()
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
				expect(ok):toBe(false)
				expect(string.find(tostring(failure), "proposal bug", 1, true) ~= nil):toBe(true)
				expect(w.find("Panel") ~= nil):toBe(true)
				w.stop()
				local fact, calls = Compose.cell(true), 0
				local w2 = mount(function(UI: FacetControls, Host: RobloxHost)
					return {
						isPresented = fact,
						onDismiss = function(): ()
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
				expect((w2.find("Panel"))):toBeNil()
				expect(calls):toBe(1)
				w2.stop()
			end,
		})

		it("a caller that re-opens inside its own close callback keeps one live surface", {
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
				expect(#w.findAll("Panel")):toBe(1)
				expect((open:peek())):toBe(true)
				w.stop()
			end,
		})

		it("open/close/branch cycles return the native tree to its baseline", {
			id = "native_popover::native Popover: callbacks that throw or re-enter, and branch cycles::open/close/branch cycles return the native tree to its baseline",
			run = function()
				local open, log, change = caller()
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						Name = "S",
						Compose.show(shown, function()
							return UI.Popover(standard(open, log, change)(UI, Host), "Tip")
						end),
					}
				end)
				local baseline = w.engine.census()
				for _ = 1, 3 do
					w.find("Open").Activated:Fire()
					w.find("ModalBack").Pressed:Fire()
					shown:set(false)
					shown:set(true)
				end
				local after = w.engine.census()
				expect(after.live):toBe(baseline.live)
				expect(after.connections):toBe(baseline.connections)
				expect((table.concat(log.dismissed, ","))):toBe("cancel,cancel,cancel")
				w.stop()
			end,
		})
	end)

	describe("native Popover: lifetime and contract", function()
		it("owner disposal releases physically and reports cancel once; two worlds stay apart", {
			id = "native_popover::native Popover: lifetime and contract::owner disposal releases physically and reports cancel once; two worlds stay apart",
			run = function()
				local open, log, change = caller()
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						Name = "S",
						Compose.show(shown, function()
							return UI.Popover(standard(open, log, change)(UI, Host), "Tip")
						end),
					}
				end)
				local open2, log2, change2 = caller()
				local w2 = mount(standard(open2, log2, change2))
				open:set(true)
				open2:set(true)
				shown:set(false)
				expect((w.find("Panel"))):toBeNil()
				expect((table.concat(log.dismissed, ","))):toBe("cancel")
				expect(#log.changes):toBe(0)
				expect(w2.find("Panel") ~= nil):toBe(true)
				expect(#log2.dismissed):toBe(0)
				w.stop()
				w2.stop()
			end,
		})

		it("the spec is closed and the contract is refused by name", {
			id = "native_popover::native Popover: lifetime and contract::the spec is closed and the contract is refused by name",
			run = function()
				local function refuses(specOf: Builder, fragment: string)
					local ok, failure = pcall(function()
						mount(specOf).stop()
					end)
					expect(ok):toBe(false)
					expect(`{fragment}: {string.find(tostring(failure), fragment, 1, true) ~= nil}`):toBe(
						`{fragment}: true`
					)
				end
				local function base(UI: FacetControls, Host: RobloxHost, extra: unknown): OverlayProps.PopoverSpec
					local spec: any = {
						isPresented = Compose.cell(false),
						trigger = UI.Button "Open" { label = "Open" },
						content = function(): Instance
							return content(UI, Host)
						end,
					}
					assert(type(extra) == "table")
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

	describe("native Popover: anchored chrome and the cancel policy (restored from 0.11 presentAnchored)", function()
		it("cancelPolicy = none keeps the panel through Cancel and an outside tap", {
			id = "native_popover::native Popover: anchored chrome and the cancel policy (restored from 0.11 presentAnchored)::cancelPolicy = none keeps the panel through Cancel and an outside tap",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change, { cancelPolicy = "none" }))
				open:set(true)
				w.find("ModalBack").Pressed:Fire()
				w.find("DismissTarget").Activated:Fire({ Position = Vector2.new(790, 590) })
				expect(w.find("Panel") ~= nil):toBe(true)
				expect(#log.changes):toBe(0)
				open:set(false)
				expect((w.find("Panel"))):toBeNil()
				w.stop()
			end,
		})

		it("modal = false is chrome: no catcher, no Cancel, no selection taken", {
			id = "native_popover::native Popover: anchored chrome and the cancel policy (restored from 0.11 presentAnchored)::modal = false is chrome: no catcher, no Cancel, no selection taken",
			run = function()
				local open, log, change = caller()
				local w = mount(function(UI: FacetControls, Host: RobloxHost)
					local spec = standard(open, log, change, { modal = false })(UI, Host)
					spec.trigger = nil
					spec.source = { rect = { x = 100, y = 100, w = 40, h = 40 } }
					return spec
				end)
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				local other = w.find("Other")
				w.gui.SelectedObject = other
				open:set(true)
				expect(w.find("Panel") ~= nil):toBe(true)
				expect((w.find("Scrim"))):toBeNil()
				expect((w.find("ModalBack"))):toBeNil()
				expect(w.find("Popup").Active):toBe(false)
				expect(w.gui.SelectedObject):toBe(other)
				open:set(false)
				expect((w.find("Panel"))):toBeNil()
				w.stop()
			end,
		})

		it("refuses a malformed modal or cancelPolicy by name", {
			id = "native_popover::native Popover: anchored chrome and the cancel policy (restored from 0.11 presentAnchored)::refuses a malformed modal or cancelPolicy by name",
			run = function()
				for _, extra: { modal: string?, cancelPolicy: string? } in
					{ { modal = "no" }, { cancelPolicy = "never" } } :: { { modal: string?, cancelPolicy: string? } }
				do
					local open, log, change = caller()
					local ok, failure = pcall(function()
						mount(standard(open, log, change, extra)).stop()
					end)
					expect(ok):toBe(false)
					local key = if extra.modal ~= nil then "modal" else "cancelPolicy"
					expect(string.find(tostring(failure), key, 1, true) ~= nil):toBe(true)
				end
			end,
		})
	end)

	describe("app.presentAnchored", function()
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

		it("builds a panel beside a rect in its own layer and close releases it", {
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
				expect(screen.Parent):toBe(target)
				expect(overlay.find(screen, "Hint").Text):toBe("Drag to steer")
				close()
				expect(screen.Parent):toBeNil()
				expect(dismissed):toEqual({ "cancel" })
				close()
				a.dispose()
			end,
		})

		it("an outside tap on a modal panel dismisses it and releases the layer", {
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
				overlay.find(screen, "DismissTarget").Activated:Fire({ Position = Vector2.new(790, 590) })
				expect(dismissed):toEqual({ "outside" })
				expect(screen.Parent):toBeNil()
				a.dispose()
			end,
		})
	end)

	describe("touch popup placement", function()
		it("prefers above on touch, flips near the top edge and follows input changes", {
			id = "native_popover::touch popup placement::prefers above on touch, flips near the top edge and follows input changes",
			run = function()
				local open, log, change = caller()
				local w = mount(standard(open, log, change, { compact = "popover" }), { motionLevel = "none" })
				local anchor = w.find("Open")
				w.engine.environment.poke(anchor, "AbsolutePosition", Vector2.new(300, 250))
				w.engine.environment.poke(anchor, "AbsoluteSize", Vector2.new(80, 44))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				open:set(true)
				local panel = w.find("Panel")
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(200, 100))
				expect(select(2, corner(panel)) + 100 < 250):toBe(true)
				w.engine.environment.poke(anchor, "AbsolutePosition", Vector2.new(300, 8))
				expect(select(2, corner(panel)) > 52):toBe(true)
				w.engine.environment.poke(anchor, "AbsolutePosition", Vector2.new(300, 250))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.KeyboardAndMouse)
				expect(select(2, corner(panel)) > 294):toBe(true)
				w.stop()
			end,
		})

		it("honors an explicit edge on touch", {
			id = "native_popover::touch popup placement::honors an explicit edge on touch",
			run = function()
				local open, log, change = caller()
				local w = mount(
					standard(open, log, change, { compact = "popover", edge = "bottom" :: "bottom" }),
					{ motionLevel = "none" }
				)
				w.engine.environment.poke(w.find("Open"), "AbsolutePosition", Vector2.new(300, 250))
				w.engine.environment.poke(w.find("Open"), "AbsoluteSize", Vector2.new(80, 44))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				open:set(true)
				w.engine.environment.poke(w.find("Panel"), "AbsoluteSize", Vector2.new(200, 100))
				expect(select(2, corner(w.find("Panel"))) > 294):toBe(true)
				w.stop()
			end,
		})
	end)
end
