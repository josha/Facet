--!strict
local NativeEngine = require("./lib/native_engine")
local Shared = require("../src/ui/types")
local OverlayTypes = require("../src/ui/overlay_types")
local NavigationProps = require("../src/ui/navigation_props")
local Verify = require("../tools/vendor/verify/src/core")
local Bdd = require("../tools/vendor/verify/src/bdd")

return function(verifyHarness: Verify.Harness)
	local test = Bdd.create(verifyHarness)
	local describe, it, expect = test.describe, test.it, test.expect
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local materialize = require("./lib/materialize")
	local fadeKit = require("./lib/fade")
	local Compose = require("../src/vendor/compose/core")
	local themes = require("../src/ui/themes")(Compose)
	local overlay = require("./lib/overlay_world")
	local placement = require("../src/ui/overlay_placement")
	local Vector2 = require("./lib/native_engine").types.Vector2

	local TIP = "Post Avatars to Marketplace"
	local LIFT = 16 * math.sqrt(2) / 2

	local function corner(panel: any): (number, number)
		return panel.Position.X.Offset - panel.AnchorPoint.X * panel.AbsoluteSize.X,
			panel.Position.Y.Offset - panel.AnchorPoint.Y * panel.AbsoluteSize.Y
	end

	local function near(actual: number, expected: number): boolean
		return math.abs(actual - expected) <= 1
	end

	local function edgeCell(value: OverlayTypes.Edge): Compose.Value<OverlayTypes.Edge>
		return Compose.cell(value)
	end

	local function tip(Host: RobloxHost): () -> TextLabel
		return function()
			return Host.TextLabel "Body" { Text = TIP }
		end
	end

	local function mount(
		specOf: (FacetControls, RobloxHost, GuiObject) -> NavigationProps.CalloutSpec,
		options: Shared.Config?
	): any
		return overlay.new(function(UI: FacetControls, Host: RobloxHost)
			local anchor = UI.Button "Plus" { label = "+" }
			local spec = specOf(UI, Host, anchor)
			return Host.Frame {
				Name = "Editor",
				Host.Frame { Name = "Bar", anchor },
				UI.Callout "Callout"(spec),
			}
		end, options)
	end

	local function buttons(root: any): { string }
		local out = {}
		for _, node in root:GetDescendants() do
			if node:IsA("TextButton") and node.Name ~= "DismissTarget" then
				table.insert(out, `{node.Parent.Name}/{node.Name}`)
			end
		end
		table.sort(out)
		return out
	end

	describe("native Callout: callbacks during a show never strand or double-close a plate", function()
		local function pair(onShow: (any) -> ()): (any, { string }, any)
			local reports: { string } = {}
			local used = Compose.cell(false)
			local gate = Compose.cell(true)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				local first = UI.Button "Plus" { label = "+" }
				local second = UI.Button "Share" { label = "Share" }
				return Host.Frame {
					Name = "Editor",
					Host.Frame { Name = "Bar", first, second },
					Compose.show(gate, function()
						return UI.Callout "First" {
							anchor = first :: GuiObject,
							priority = 2,
							content = tip(Host),
							featureUsed = used,
							onShow = function(): ()
								onShow({ used = used, gate = gate })
							end,
							onRetire = function(reason: "action" | "dismissed" | "featureUsed" | "seen" | "tapAway")
								table.insert(reports, reason)
							end,
						}
					end),
					UI.Callout "Second" {
						anchor = second :: GuiObject,
						priority = 1,
						content = function(): Instance
							return Host.TextLabel "SecondBody" { Text = "Share it" }
						end,
						onRetire = function() end,
					},
				}
			end, { motionLevel = "none" })
			return w, reports, gate
		end

		it("dismissing from inside the plate hands the selection to the anchor at once", {
			id = "native_callout_help::native Callout: callbacks during a show never strand or double-close a plate::dismissing from inside the plate hands the selection to the anchor at once",
			run = function()
				local w = mount(function(_, Host: RobloxHost, anchor: GuiObject)
					return { anchor = anchor, onRetire = function() end, content = tip(Host) }
				end)
				w.advance(0.5)
				local dismiss = w.find("Dismiss")
				expect(dismiss ~= nil):toBe(true)
				w.gui.SelectedObject = dismiss
				dismiss.Activated:Fire()
				expect(w.gui.SelectedObject):toBe(w.find("Plus"))
				w.stop()
			end,
		})

		it("disposal inside onShow releases the queue slot", {
			id = "native_callout_help::native Callout: callbacks during a show never strand or double-close a plate::disposal inside onShow releases the queue slot",
			run = function()
				local w = pair(function(state)
					state.gate:set(false)
				end)
				expect((w.find("Body"))):toBeNil()
				expect(w.find("SecondBody") ~= nil):toBe(true)
				expect(#w.findAll("CalloutPanel")):toBe(1)
				w.stop()
			end,
		})

		it("an ordinary throw in onShow still shows the plate and keeps the slot accounting", {
			id = "native_callout_help::native Callout: callbacks during a show never strand or double-close a plate::an ordinary throw in onShow still shows the plate and keeps the slot accounting",
			run = function()
				local failures: { string } = {}
				local reports: { string } = {}
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					local first = UI.Button "Plus" { label = "+" }
					local second = UI.Button "Share" { label = "Share" }
					return Host.Frame {
						Name = "Editor",
						Host.Frame { Name = "Bar", first, second },
						UI.Callout "First" {
							anchor = first :: GuiObject,
							priority = 2,
							content = tip(Host),
							onShow = function(): ()
								error("caller bug")
							end,
							onRetire = function(reason: "action" | "dismissed" | "featureUsed" | "seen" | "tapAway")
								table.insert(reports, reason)
							end,
						},
						UI.Callout "Second" {
							anchor = second :: GuiObject,
							priority = 1,
							content = function(): Instance
								return Host.TextLabel "SecondBody" { Text = "Share it" }
							end,
							onRetire = function() end,
						},
					}
				end, {
					onError = function(failure: unknown)
						table.insert(failures, tostring(failure))
					end,
				})
				expect(w.find("Body") ~= nil):toBe(true)
				expect((w.find("SecondBody"))):toBeNil()
				expect(#failures):toBe(1)
				expect(string.find(failures[1], "caller bug", 1, true) ~= nil):toBe(true)
				w.find("Dismiss").Activated:Fire()
				expect((table.concat(reports, ","))):toBe("dismissed")
				expect((w.find("Body"))):toBeNil()
				expect(w.find("SecondBody") ~= nil):toBe(true)
				w.stop()
			end,
		})
	end)

	describe("native Callout: two worlds and a recycled source keep their own resources", function()
		it("disposing one world's callout never touches another world's", {
			id = "native_callout_help::native Callout: two worlds and a recycled source keep their own resources::disposing one world's callout never touches another world's",
			run = function()
				local gate = Compose.cell(true)
				local a = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Plus" { label = "+" }
					return Host.Frame {
						Host.Frame { anchor },
						Compose.show(gate, function()
							return UI.Callout "Callout" {
								anchor = anchor :: GuiObject,
								content = tip(Host),
								onRetire = function() end,
							}
						end),
					}
				end)
				local b = mount(function(_, Host: RobloxHost, anchor: GuiObject)
					return { anchor = anchor, onRetire = function() end, content = tip(Host) }
				end)
				expect(a.find("CalloutPanel") ~= nil and b.find("CalloutPanel") ~= nil):toBe(true)
				gate:set(false)
				expect((a.find("CalloutPanel"))):toBeNil()
				expect(b.find("CalloutPanel") ~= nil):toBe(true)
				a.stop()
				b.stop()
			end,
		})
	end)

	describe("native Callout: rich parts", function()
		it("side callouts use the available height and react to edge changes", function(own)
			local edge = edgeCell("trailing")
			local w = mount(function(_, _, anchor: GuiObject)
				local fields: NavigationProps.CalloutSpec =
					{ anchor = anchor, onRetire = function() end, title = "Guide", edge = edge }
				return fields
			end, { motionLevel = "none" })
			own(w.stop)
			w.at(w.find("Plus"), 300, 250)
			w.size(w.find("Plus"), 80, 44)
			w.size(w.find("CalloutContent"), 248, 400)
			w.advance(1 / 60, 3)
			local body = w.find("CalloutBody")
			expect(body.Size.Y.Offset):toBe(400)
			edge:set("leading")
			expect(body.Size.Y.Offset):toBe(400)
			edge:set("top")
			expect(body.Size.Y.Offset < 400):toBe(true)
		end)
		it("fixed width teaching content uses the plate's bounded native cross axis", function(own)
			local w = mount(function(_, Host: RobloxHost, anchor: GuiObject)
				return {
					anchor = anchor,
					onRetire = function() end,
					title = "Open garage",
					content = function()
						return Host.Frame "HelpText" {
							Size = NativeEngine.types.UDim2.fromOffset(260, 0),
							AutomaticSize = NativeEngine.types.Enum.AutomaticSize.Y,
							Host.TextLabel "Instruction" {
								Text = "Open the garage to choose a vehicle and review its upgrades.",
								TextWrapped = true,
								Size = NativeEngine.types.UDim2.fromScale(1, 0),
								AutomaticSize = NativeEngine.types.Enum.AutomaticSize.Y,
							},
						}
					end,
				}
			end)
			local content = w.find("CalloutContent")
			local layout = content:FindFirstChildWhichIsA("UIListLayout")
			expect(layout.FillDirection):toBe(w.Enum.FillDirection.Vertical)
			expect(layout.HorizontalFlex):toBe(w.Enum.UIFlexAlignment.Fill)
			expect(content.Size.X.Scale):toBe(1)
			expect(content.AutomaticSize):toBe(w.Enum.AutomaticSize.Y)
			expect(w.find("HelpText").Parent):toBe(content)
			expect(w.find("Instruction").TextWrapped):toBe(true)
			w.stop()
		end)
		it("the full composition paints every part, and one or two actions replace the bottom dismiss", {
			id = "native_callout_help::native Callout: rich parts::the full composition paints every part, and one or two actions replace the bottom dismiss",
			run = function()
				local pressed, reports = {}, {}
				local w = mount(function(_, Host: RobloxHost, anchor: GuiObject)
					return {
						anchor = anchor,
						content = tip(Host),
						title = "Try the editor",
						media = { image = "rbxassetid://1", aspectRatio = 2 },
						steps = { index = 2, count = 3 },
						closeButton = true,
						actions = {
							{
								id = "Later",
								label = "Later",
								onActivate = function(): ()
									table.insert(pressed, "Later")
								end,
							},
							{
								id = "Go",
								label = "Show me",
								role = "default" :: "default",
								onActivate = function(): ()
									table.insert(pressed, "Go")
								end,
							},
						},
						onRetire = function(reason: string)
							table.insert(reports, reason)
						end,
					}
				end)
				local panel = w.find("CalloutPanel")
				expect(overlay.find(panel, "Title").Text):toBe("Try the editor")
				local media = overlay.find(panel, "Media")
				expect(media.Size.X.Scale):toBe(1)
				expect(media:FindFirstChildWhichIsA("UIAspectRatioConstraint").AspectRatio):toBe(2)
				expect(overlay.find(panel, "Steps").Text):toBe("2 of 3")
				expect(overlay.find(panel, "Body").Text):toBe(TIP)
				expect((table.concat(buttons(panel), ","))):toBe("Actions/Go,Actions/Later,Header/Close")
				expect((overlay.find(panel, "Dismiss"))):toBeNil()
				expect((overlay.find(panel, "Go"):GetAttribute("appearance"))):toBe("emphasis")
				expect((overlay.find(panel, "Later"):GetAttribute("appearance"))):toBe("standard")
				overlay.find(panel, "Go").Activated:Fire()
				expect((table.concat(pressed, ","))):toBe("Go")
				expect((table.concat(reports, ","))):toBe("action")
				expect((w.find("CalloutPanel"))):toBeNil()
				w.stop()
			end,
		})

		it("an action retires its own generation once, and never a newer one it presented", {
			id = "native_callout_help::native Callout: rich parts::an action retires its own generation once, and never a newer one it presented",
			run = function()
				local generation, reports = Compose.cell(1), {}
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Plus" { label = "+" }
					return Host.Frame {
						Host.Frame { anchor },
						Compose.keyed({
							from = function(use: any)
								return { use(generation) }
							end,
							render = function(): GuiObject
								return UI.Callout "Callout" {
									anchor = anchor :: GuiObject,
									content = tip(Host),
									actions = {
										{
											id = "Again",
											label = "Again",
											onActivate = function(): ()
												generation:set(generation:peek() + 1)
												error("caller bug after rearm")
											end,
										},
									},
									onRetire = function(
										reason: "action" | "dismissed" | "featureUsed" | "seen" | "tapAway"
									)
										table.insert(reports, reason)
									end,
								}
							end,
						}),
					}
				end)
				local first = w.find("CalloutPanel")
				local ok = pcall(function()
					overlay.find(first, "Again").Activated:Fire()
				end)
				expect(ok):toBe(false)
				expect((generation:peek())):toBe(2)
				local panels = w.findAll("CalloutPanel")
				expect(#panels):toBe(1)
				expect(panels[1] ~= first):toBe(true)
				expect(overlay.find(panels[1], "Body") ~= nil):toBe(true)
				expect(#reports):toBe(0)
				w.stop()
			end,
		})

		it("a throwing action still retires the presentation it belonged to, exactly once", {
			id = "native_callout_help::native Callout: rich parts::a throwing action still retires the presentation it belonged to, exactly once",
			run = function()
				local reports = {}
				local w = mount(function(_, Host: RobloxHost, anchor: GuiObject)
					return {
						anchor = anchor,
						content = tip(Host),
						actions = {
							{
								id = "Boom",
								label = "Boom",
								onActivate = function(): ()
									error("caller bug")
								end,
							},
						},
						onRetire = function(reason: string)
							table.insert(reports, reason)
						end,
					}
				end)
				local boom = overlay.find(w.find("CalloutPanel"), "Boom")
				w.gui.SelectedObject = boom
				expect((pcall(function()
					w.action("Activate").Pressed:Fire()
				end))):toBe(false)
				expect((table.concat(reports, ","))):toBe("action")
				expect((w.find("CalloutPanel"))):toBeNil()
				w.stop()
			end,
		})

		it("a disabled action cannot fire", {
			id = "native_callout_help::native Callout: rich parts::a disabled action cannot fire",
			run = function()
				local fired = false
				local w = mount(function(_, Host: RobloxHost, anchor: GuiObject)
					return {
						anchor = anchor,
						onRetire = function() end,
						content = tip(Host),
						actions = {
							{
								id = "Nope",
								label = "Nope",
								enabled = false,
								onActivate = function(): ()
									fired = true
								end,
							},
						},
					}
				end)
				local nope = overlay.find(w.find("CalloutPanel"), "Nope")
				expect(nope.Interactable):toBe(false)
				nope.Activated:Fire()
				expect(fired):toBe(false)
				expect(w.find("CalloutPanel") ~= nil):toBe(true)
				w.stop()
			end,
		})

		it("closeButton adds a top close and keeps the legacy bottom dismiss when there are no actions", {
			id = "native_callout_help::native Callout: rich parts::closeButton adds a top close and keeps the legacy bottom dismiss when there are no actions",
			run = function()
				local reports = {}
				local w = mount(function(_, Host: RobloxHost, anchor: GuiObject)
					return {
						anchor = anchor,
						content = tip(Host),
						closeButton = true,
						onRetire = function(reason: string)
							table.insert(reports, reason)
						end,
					}
				end)
				local panel = w.find("CalloutPanel")
				expect((table.concat(buttons(panel), ","))):toBe("CalloutContent/Dismiss,Header/Close")
				local close = overlay.find(panel, "Close")
				expect(close.Size.X.Offset >= 44 and close.Size.Y.Offset >= 44):toBe(true)
				close.Activated:Fire()
				expect((table.concat(reports, ","))):toBe("dismissed")
				expect((w.find("CalloutPanel"))):toBeNil()
				w.stop()
			end,
		})

		it("an empty composition and malformed parts are refused by name", {
			id = "native_callout_help::native Callout: rich parts::an empty composition and malformed parts are refused by name",
			run = function()
				local print = function() end
				local malformed: { { [string]: any } } = {
					{},
					{ closeButton = true },
					{ media = { image = "x", aspectRatio = 1, height = 20 } },
					{ media = { image = "x" } },
					{ media = { image = "x", aspectRatio = -1 } },
					{ media = { image = "x", height = 10, scaleMode = "tile" :: "tile" } },
					{ media = { image = "x", height = 10, extra = 1 } },
					{ steps = { index = 0, count = 2 } },
					{ steps = { index = 3, count = 2 } },
					{ steps = { index = 1.5, count = 2 } },
					{
						actions = {
							{ id = "A", label = "A", onActivate = print },
							{ id = "B", label = "B", onActivate = print },
							{ id = "C", label = "C", onActivate = print },
						},
					},
					{
						actions = {
							{ id = "A", label = "A", onActivate = print },
							{ id = "A", label = "B", onActivate = print },
						},
					},
					{ actions = { { id = "A", label = "A" } } },
					{ actions = { { id = "A", label = "A", onActivate = print, role = "primary" :: "primary" } } },
					{ closeButton = "yes", title = "T" },
					{ title = 4 },
				}
				for index, bad in malformed do
					local ok = pcall(function()
						mount(function(_, _, anchor: GuiObject)
							local fields = table.clone(bad)
							fields.anchor = anchor
							fields.onRetire = function() end
							return fields
						end).stop()
					end)
					expect(`case {index}: {ok}`):toBe(`case {index}: false`)
				end
			end,
		})
	end)

	describe("native help: the structured form and the live plate", function()
		local function helped(value: any): any
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame { Name = "Screen", UI.Button "Post" { label = "Post", help = value } }
			end, { motionLevel = "none" })
			local post = w.find("Post")
			w.engine.environment.poke(post, "AbsolutePosition", Vector2.new(300, 200))
			w.engine.environment.poke(post, "AbsoluteSize", Vector2.new(80, 44))
			w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
			w.gui.SelectedObject = post
			w.advance(0.5)
			return w
		end

		it("a title, a body and a display-only shortcut paint in one plate", {
			id = "native_callout_help::native help: the structured form and the live plate::a title, a body and a display-only shortcut paint in one plate",
			run = function()
				local before = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						Name = "Screen",
						UI.Button "Post" { label = "Post", help = "Posts it" },
					}
				end)
				local post = before.find("Post")
				before.engine.environment.poke(before.input, "PreferredInput", before.Enum.PreferredInput.Gamepad)
				before.gui.SelectedObject = post
				before.advance(0.5)
				local contexts = 0
				for _, node in before.screen:GetDescendants() do
					if node:IsA("InputContext") then
						contexts += 1
					end
				end
				before.stop()
				local w =
					helped({ title = "Post", body = "Posts this avatar", shortcut = { { "Ctrl", "P" }, { "F2" } } })
				expect(w.find("HelpTitle").Text):toBe("Post")
				expect(w.find("HelpText").Text):toBe("Posts this avatar")
				expect(w.find("HelpShortcut").Text):toBe("Ctrl+P or F2")
				local after = 0
				for _, node in w.screen:GetDescendants() do
					if node:IsA("InputContext") then
						after += 1
					end
				end
				expect(after):toBe(contexts)
				w.stop()
			end,
		})

		it("edge and align place the plate", {
			id = "native_callout_help::native help: the structured form and the live plate::edge and align place the plate",
			run = function()
				local w = helped({ body = "Posts it", edge = "trailing" :: "trailing", align = "end" :: "end" })
				local panel = w.find("Help")
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(120, 30))
				local expected = placement.solve({
					source = { x = 300, y = 200, w = 80, h = 44 },
					size = { w = 120, h = 30 },
					safe = { x = 8, y = 8, w = 800 - 16, h = 600 - 16 },
					edge = "trailing" :: "trailing",
					align = "end" :: "end",
					gap = 6 + LIFT,
				})
				local x, y = corner(panel)
				expect((near(x, expected.x))):toBe(true)
				expect((near(x, 300 + 80 + 6 + LIFT))):toBe(true)
				expect((near(y, 200 + 44 - 30))):toBe(true)
				w.stop()
			end,
		})

		it("the string form paints exactly as before: no title node", {
			id = "native_callout_help::native help: the structured form and the live plate::the string form paints exactly as before: no title node",
			run = function()
				local w = helped("Posts this avatar")
				expect((w.find("HelpTitle"))):toBeNil()
				expect((w.find("HelpShortcut"))):toBeNil()
				expect(w.find("HelpText").Text):toBe("Posts this avatar")
				local panel = w.find("Help")
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(100, 30))
				local x, y = corner(panel)
				expect((near(y, 200 - 30 - 6 - LIFT))):toBe(true)
				expect((near(x, 300 + 40 - 50))):toBe(true)
				expect(w.find("HelpTail") ~= nil and w.find("HelpTailSeam") == nil and w.find("Outline") ~= nil):toBe(
					true
				)
				expect(w.find("HelpTail").Size.X.Offset):toBe(16)
				expect((near(w.find("HelpTail").Position.Y.Offset, 200 - 6 - LIFT))):toBe(true)
				expect((w.find("HelpTail"):HasTag("facet-tail"))):toBe(true)
				w.stop()
			end,
		})

		it("malformed tables are refused by name at construction", {
			id = "native_callout_help::native help: the structured form and the live plate::malformed tables are refused by name at construction",
			run = function()
				for index, bad in
					{
						{ title = "T" } :: any,
						{ body = "" },
						{ body = "Posts", extra = true },
						{ body = "Posts", shortcut = { "Ctrl" } },
						{ body = "Posts", shortcut = { {} } },
						{ body = "Posts", edge = "overlap" :: "overlap" },
						{ body = "Posts", align = "middle" :: "middle" },
						{ body = 4 },
					}
				do
					local ok, failure = pcall(function()
						helped(bad).stop()
					end)
					expect(`case {index}: {ok}`):toBe(`case {index}: false`)
					expect(string.find(tostring(failure), "help", 1, true) ~= nil):toBe(true)
				end
				helped({ title = "Post", body = "" }).stop()
			end,
		})

		it("safe insets that grow under a live plate keep it inside the new safe box", {
			id = "native_callout_help::native help: the structured form and the live plate::safe insets that grow under a live plate keep it inside the new safe box",
			run = function()
				local w = helped({ body = "Posts it", edge = "trailing" :: "trailing" })
				local panel = w.find("Help")
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(200, 30))
				expect((near((corner(panel)), 386 + LIFT))):toBe(true)
				w.engine.environment.poke(w.screen, "AbsoluteSize", Vector2.new(500, 600))
				expect((corner(panel)) + 200 <= 500 - 8 + 0.5):toBe(true)
				w.stop()
			end,
		})
	end)

	describe("native help: the plate arrives as one unit", function()
		local function hovered(options: any?): any
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame {
					Name = "Screen",
					UI.Button "Post" {
						label = "Post",
						help = {
							title = "Save",
							body = "Saves your setup",
							shortcut = { { "Ctrl", "S" } },
							edge = "top" :: "top",
						},
					},
				}
			end, options)
			w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
			w.gui.SelectedObject = w.find("Post")
			w.advance(0.45)
			return w
		end

		it("the whole plate fades once at rest over the theme's normal motion duration", {
			id = "native_callout_help::native help: the plate arrives as one unit::the whole plate fades once at rest over the theme's normal motion duration",
			run = function()
				local themes = require("../src/ui/themes")(Compose)
				for _, duration in { 0.2, 0.4 } do
					local package = themes.neutralPackage()
					package.metrics.motion.normal = duration
					local fadeShare = if duration == 0.2 then 0.6 else 1
					package.metrics.motion.presentFadeIn = fadeShare
					assert(package.metrics.motion.easing).present = if duration == 0.2 then "outCubic" else "outQuad"
					local defined = themes.define(package)
					local w = hovered({ theme = assert(defined) })
					local panel = w.find("Help")
					w.engine.environment.poke(panel, "AbsoluteSize", w.Vector2.new(120, 60))
					local labels: { TextLabel } = { w.find("HelpTitle"), w.find("HelpText"), w.find("HelpShortcut") }
					for index, label in labels do
						w.engine.environment.poke(label, "AbsolutePosition", w.Vector2.new(8, 6 + (index - 1) * 16))
						w.engine.environment.poke(label, "AbsoluteSize", w.Vector2.new(104, 16))
						w.engine.environment.poke(label, "TextBounds", w.Vector2.new(80, 16))
					end
					w.advance(0, 2)
					expect(fadeKit.of(panel)):toBe(1)
					local position, anchor = panel.Position, panel.AnchorPoint
					local previous = 1
					local easing = if duration == 0.2 then Compose.easing.outCubic else Compose.easing.outQuad
					for frame = 1, 24 do
						w.advance(duration / 24)
						local alpha = fadeKit.of(panel)
						expect(math.abs(alpha - (1 - math.clamp(easing(frame / 24) / easing(fadeShare), 0, 1))) < 1e-6):toBe(
							true
						)
						expect(alpha <= previous):toBe(true)
						expect(materialize.of(panel).Scale):toBe(1)
						expect(panel.Position):toBe(position)
						expect(panel.AnchorPoint):toBe(anchor)
						expect(panel:FindFirstChild("PresentationContent", true)):toBe(nil)
						local group = panel:FindFirstChild("Fade")
						expect(math.abs(group.GroupTransparency - alpha) < 1e-6):toBe(true)
						for index, label in labels do
							expect(label:IsDescendantOf(group)):toBe(true)
							expect(label.TextTransparency):toBe(0)
							expect(label.AbsolutePosition - panel.AbsolutePosition):toBe(
								w.Vector2.new(8, 6 + (index - 1) * 16)
							)
						end
						previous = alpha
					end
					expect(fadeKit.of(panel)):toBe(0)
					w.advance(duration, 24)
					expect(fadeKit.of(panel)):toBe(0)
					expect(panel.Position):toBe(position)
					w.stop()
				end
			end,
		})

		it("reduced motion shows the plate whole once its size has held", {
			id = "native_callout_help::native help: the plate arrives as one unit::reduced motion shows the plate whole once its size has held",
			run = function()
				local w = hovered({ motionLevel = "none" })
				local panel = w.find("Help")
				w.engine.environment.poke(panel, "AbsoluteSize", w.Vector2.new(120, 40))
				w.advance(1 / 60, 2)
				expect((fadeKit.of(panel))):toBe(0)
				expect(materialize.of(panel).Scale):toBe(1)
				w.stop()
			end,
		})
	end)

	describe("native Callout: the plate and its tail arrive together", function()
		it("uses theme arrow artwork on every edge and restores native paint on theme switches", {
			id = "native_callout_help::skinned-tail-outline-theme-switch",
			run = function()
				local neutral = themes.neutralPackage()
				local ornate = require("../examples/themes/fantasy_ornate").build(themes)
				local withoutArrow = require("../examples/themes/fantasy_ornate").definition(themes)
				withoutArrow.chrome.panelTail = nil
				local defined = themes.define(withoutArrow)
				local framed = assert(defined)
				local selected = Compose.cell(neutral)
				local edge = edgeCell("bottom")
				local w = mount(function(_, _, anchor: GuiObject)
					local fields: NavigationProps.CalloutSpec =
						{ anchor = anchor, onRetire = function() end, title = "Start here", edge = edge }
					return fields
				end, { theme = selected, motionLevel = "none" })
				w.engine.environment.poke(w.find("Plus"), "AbsolutePosition", w.Vector2.new(320, 240))
				w.engine.environment.poke(w.find("Plus"), "AbsoluteSize", w.Vector2.new(80, 44))
				w.engine.environment.poke(w.find("CalloutPanel"), "AbsoluteSize", w.Vector2.new(280, 120))
				local outline: Path2D = w.find("Outline")
				local sides: { OverlayTypes.Edge } = { "bottom", "top", "leading", "trailing" }
				for _, side in sides do
					edge:set(side)
					expect(outline.Closed):toBe(true)
					expect(#outline:GetControlPoints()):toBe(11)
					selected:set(ornate)
					expect(outline.Closed):toBe(false)
					expect(#outline:GetControlPoints()):toBe(0)
					expect(outline.Visible):toBe(false)
					local arrow = w.find("Arrow")
					local content: GuiObject = w.find("CalloutContent")
					local artwork: GuiObject = w.find("ArrowArtwork")
					expect(artwork:IsDescendantOf(w.find("CalloutPanel"))):toBe(true)
					expect(artwork.ZIndex < content.ZIndex):toBe(true)
					expect(arrow.Size.X.Offset):toBe(32)
					expect(arrow.Size.Y.Offset):toBe(20)
					expect(arrow.Rotation):toBe(({ bottom = 0, top = 180, leading = 90, trailing = -90 })[side])
					expect(w.find("ArrowArtwork"):FindFirstChildWhichIsA("ImageLabel", true).Image):toBe(
						"rbxassetid://70885878191900"
					)
					selected:set(framed)
					expect(outline.Visible):toBe(true)
					expect(outline.Closed):toBe(false)
					expect(#outline:GetControlPoints()):toBe(3)
					selected:set(neutral)
					expect(outline.Visible):toBe(true)
					expect(arrow.Rotation):toBe(45)
				end
				expect(outline.Closed):toBe(true)
				expect(#outline:GetControlPoints()):toBe(11)
				w.stop()
			end,
		})
		it("the panel and the tail both wait for the first styled frame and fade over the short duration", {
			id = "native_callout_help::native Callout: the plate and its tail arrive together::the panel and the tail both wait for the first styled frame and fade over the short duration",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Plus" { label = "+" }
					return Host.Frame {
						Name = "Editor",
						Host.Frame { Name = "Bar", anchor },
						UI.Callout "Tip" {
							anchor = anchor :: GuiObject,
							isPresented = true,
							content = tip(Host),
							onRetire = function() end,
						},
					}
				end, nil, { runService = true })
				local panel, arrow = w.find("CalloutPanel"), w.find("Arrow")
				local content = w.find("CalloutContent")
				local contentSize, contentAutomatic = content.Size, content.AutomaticSize
				expect(panel.Visible):toBe(false)
				expect(arrow.Visible):toBe(false)
				w.engine.environment.poke(panel, "AbsoluteSize", w.Vector2.new(280, 120))
				w.advance(1 / 60, 2)
				expect(fadeKit.of(panel)):toBe(1)
				expect(panel.Visible):toBe(true)
				expect(arrow.Visible):toBe(true)
				local previous, intermediate = 1, 0
				for _ = 1, math.ceil(themes.neutralPackage().metrics.motion.fast * 60) + 1 do
					w.advance(1 / 60)
					local alpha = fadeKit.of(panel)
					expect(content.Size):toBe(contentSize)
					expect(content.AutomaticSize):toBe(contentAutomatic)
					expect(alpha <= previous):toBe(true)
					expect(panel.Visible):toBe(arrow.Visible)
					if alpha > 0 and alpha < 1 then
						intermediate += 1
					end
					previous = alpha
				end
				expect(intermediate > 0):toBe(true)
				expect((fadeKit.of(panel))):toBe(0)
				w.stop()
			end,
		})
		it("the plate's own paint waits for its fade group's first drawn frame, so text and panel appear as one", {
			id = "native_callout_help::native Callout: the plate and its tail arrive together::the plate's own paint waits for its fade group's first drawn frame, so text and panel appear as one",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					local anchor = UI.Button "Plus" { label = "+" }
					return Host.Frame {
						Name = "Editor",
						Host.Frame { Name = "Bar", anchor },
						UI.Callout "Tip" {
							anchor = anchor :: GuiObject,
							isPresented = true,
							content = tip(Host),
							onRetire = function() end,
						},
					}
				end, nil, { runService = true })
				local panel = w.find("CalloutPanel")
				expect(panel.Visible):toBe(false)
				w.engine.environment.poke(panel, "AbsoluteSize", w.Vector2.new(280, 120))
				w.advance(0.01)
				local group = panel:FindFirstChild("Fade")
				expect(group ~= nil and group:IsA("CanvasGroup")):toBe(true)
				expect((fadeKit.of(panel))):toBe(1)
				expect(group.GroupTransparency > 0.98):toBe(true)
				w.advance(1 / 60, 2)
				w.advance(0.01)
				expect(fadeKit.of(panel) < 1):toBe(true)
				expect(math.abs(group.GroupTransparency - fadeKit.of(panel)) < 1e-6):toBe(true)
				w.advance(0.2)
				expect((panel:FindFirstChild("Fade"))):toBeNil()
				expect((fadeKit.of(panel))):toBe(0)
				w.stop()
			end,
		})
	end)

	describe("touch contextual text placement", function()
		it("prefers above for default callouts, falls back and honors an explicit edge", {
			id = "native_callout_help::touch contextual text placement::prefers above for default callouts, falls back and honors an explicit edge",
			run = function()
				for _, edge in { "default", "bottom" } :: { "bottom" | "default" } do
					local w = mount(function(_, Host: RobloxHost, anchor: GuiObject)
						return {
							anchor = anchor,
							onRetire = function() end,
							content = tip(Host),
							edge = if edge == "default" then nil else edge,
						}
					end, { motionLevel = "none" })
					local anchor, panel = w.find("Plus"), w.find("CalloutPanel")
					w.engine.environment.poke(anchor, "AbsolutePosition", Vector2.new(300, 250))
					w.engine.environment.poke(anchor, "AbsoluteSize", Vector2.new(80, 44))
					w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(280, 100))
					w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
					local _, y = corner(panel)
					expect(if edge == "default" then y + 100 < 250 else y > 294):toBe(true)
					w.engine.environment.poke(anchor, "AbsolutePosition", Vector2.new(300, 8))
					expect(select(2, corner(panel)) > 52):toBe(true)
					w.engine.environment.poke(anchor, "AbsolutePosition", Vector2.new(300, 250))
					w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.KeyboardAndMouse)
					expect(select(2, corner(panel)) > 294):toBe(true)
					w.stop()
				end
			end,
		})

		it("keeps long-press help above and flips it when the top has no room", {
			id = "native_callout_help::touch contextual text placement::keeps long-press help above and flips it when the top has no room",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { UI.Button "HelpAnchor" { label = "Help", help = "Full action name" } }
				end, { motionLevel = "none" })
				local anchor = w.find("HelpAnchor")
				w.engine.environment.poke(anchor, "AbsolutePosition", Vector2.new(300, 200))
				w.engine.environment.poke(anchor, "AbsoluteSize", Vector2.new(80, 44))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				anchor.TouchLongPress:Fire({ Vector2.new(320, 220) }, w.Enum.UserInputState.Begin)
				local panel = w.find("Help")
				w.engine.environment.poke(panel, "AbsoluteSize", Vector2.new(160, 32))
				expect(select(2, corner(panel)) + 32 < 200):toBe(true)
				w.engine.environment.poke(anchor, "AbsolutePosition", Vector2.new(300, 8))
				local x, y = corner(panel)
				expect(x >= 320 + 44 or x + 160 <= 320 - 44 or y >= 28 + 44):toBe(true)
				w.stop()
			end,
		})
	end)

	describe("help while using the pointer", function()
		it("waits for idle movement and all mouse buttons to be released, even over another row", {
			id = "native_callout_help::help while using the pointer::waits for idle movement and all mouse buttons to be released, even over another row",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Button "First" { label = "First", help = "First help" },
						UI.Button "Second" { label = "Second", help = "Second help" },
					}
				end, { motionLevel = "none" })
				local E = w.Enum
				w.engine.environment.poke(w.input, "PreferredInput", E.PreferredInput.KeyboardAndMouse)
				w.engine.environment.poke(w.find("First"), "GuiState", E.GuiState.Hover)
				w.advance(0.3)
				for _ = 1, 4 do
					w.input.InputChanged:Fire({ UserInputType = E.UserInputType.MouseMovement })
					w.advance(0.3)
					expect((w.find("Help"))):toBeNil()
				end
				w.advance(0.2)
				expect(w.find("HelpText").Text):toBe("First help")
				w.input.InputChanged:Fire({ UserInputType = E.UserInputType.MouseWheel })
				expect((w.find("Help"))):toBeNil()
				w.input.InputBegan:Fire({ UserInputType = E.UserInputType.MouseButton1 })
				w.engine.environment.poke(w.find("First"), "GuiState", E.GuiState.Idle)
				w.engine.environment.poke(w.find("Second"), "GuiState", E.GuiState.Hover)
				w.advance(1)
				expect((w.find("Help"))):toBeNil()
				w.input.InputBegan:Fire({ UserInputType = E.UserInputType.MouseButton2 })
				w.input.InputEnded:Fire({ UserInputType = E.UserInputType.MouseButton1 })
				w.advance(1)
				expect((w.find("Help"))):toBeNil()
				w.input.InputEnded:Fire({ UserInputType = E.UserInputType.MouseButton2 })
				w.advance(0.3)
				expect((w.find("Help"))):toBeNil()
				w.advance(0.2)
				expect(w.find("HelpText").Text):toBe("Second help")
				w.stop()
				expect((NativeEngine.connections(w.input.InputChanged))):toBe(0)
			end,
		})

		it("shares native GUI mouse activity when plugin input bypasses UserInputService", {
			id = "native_callout_help::help while using the pointer::shares native GUI mouse activity when plugin input bypasses UserInputService",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame {
						UI.Button "First" { label = "First", help = "First help" },
						UI.Button "Second" { label = "Second", help = "Second help" },
					}
				end, { motionLevel = "none" })
				local first, second, E = w.find("First"), w.find("Second"), w.Enum
				w.engine.environment.poke(first, "GuiState", E.GuiState.Hover)
				for _ = 1, 4 do
					first.MouseMoved:Fire(10, 10)
					w.advance(0.3)
					expect((w.find("Help"))):toBeNil()
				end
				local button = { UserInputType = E.UserInputType.MouseButton1 }
				first.InputBegan:Fire(button)
				w.engine.environment.poke(first, "GuiState", E.GuiState.Idle)
				w.engine.environment.poke(second, "GuiState", E.GuiState.Hover)
				w.advance(1)
				expect((w.find("Help"))):toBeNil()
				first.InputEnded:Fire(button)
				w.advance(0.5)
				expect(w.find("HelpText").Text):toBe("Second help")
				w.input.WindowFocusReleased:Fire()
				w.advance(1)
				expect((w.find("Help"))):toBeNil()
				w.input.WindowFocused:Fire()
				w.advance(0.3)
				expect((w.find("Help"))):toBeNil()
				w.advance(0.2)
				expect(w.find("HelpText").Text):toBe("Second help")
				w.stop()
				expect((NativeEngine.connections(w.input.InputChanged))):toBe(0)
			end,
		})

		it("carries a nested stylesheet to its overlay without restyling sibling content", {
			id = "native_callout_help::help while using the pointer::carries a nested stylesheet to its overlay without restyling sibling content",
			run = function()
				local sheet: any
				local link: StyleLink
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					sheet = Host.StyleSheet {}
					link = Host.StyleLink { StyleSheet = Compose.static(sheet) }
					return Host.Frame {
						sheet,
						link,
						UI.Button "Styled" { label = "Styled", help = "Styled help" },
					}
				end, { motionLevel = "none" })
				w.gui.SelectedObject = w.find("Styled")
				w.advance(0.5)
				local panel = w.find("Help")
				local inherited = panel.Parent:FindFirstChildWhichIsA("StyleLink")
				expect(inherited ~= nil):toBe(true)
				expect(inherited.StyleSheet):toBe(sheet)
				expect((w.screen:FindFirstChildWhichIsA("StyleLink"))):toBeNil()
				local replacement = w.engine.new("StyleSheet")
				link.StyleSheet = replacement
				expect(inherited.StyleSheet):toBe(replacement)
				w.gui.SelectedObject = nil
				expect((inherited:isDestroyed())):toBe(true)
				expect((sheet:isDestroyed())):toBe(false)
				w.stop()
			end,
		})
	end)
end
