--!strict
local Verify = require("../tools/vendor/verify/src/core")
local VerifyRoblox = require("../tools/vendor/verify/src/roblox")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")

	local function dialog(
		UI: FacetControls,
		Host: RobloxHost,
		name: string,
		open: typeof(require("@repo/tools/typecheck/aliases").BooleanCell)
	): GuiObject
		return UI.Dialog(name)({
			isPresented = open,
			onPresentedChange = function(value: boolean)
				open:set(value)
			end,
			title = name,
			content = function(): Instance
				return Host.TextLabel "Line" { Text = name }
			end,
		})
	end

	local function modalOf(w: { findAll: (string) -> { Instance } }, name: string): Frame
		for _, modal in w.findAll("DialogModal") do
			if modal:IsA("Frame") and overlay.find(modal, "Title").Text == name then
				return modal
			end
		end
		error(`missing modal {name}`)
	end

	verifyHarness:suite("native modal: the scrim sinks input", function()
		for _, touch in { false, true } do
			verifyHarness:case(
				`an open Dialog blocks {if touch then "touch" else "wheel"} scrolling until it closes`,
				function(check)
					local w = require("./lib/modal_scroll_world")("Dialog")
					check:defer(w.stop)
					local before = w.list.CanvasPosition.Y
					w.open:set(true)
					w.settle()
					w.scroll(touch)
					Verify.expect(w.list.CanvasPosition.Y):toBe(before)
					Verify.expect(w.page.CanvasPosition.Y):toBe(0)
					Verify.expect(w.open:peek()):toBe(true)
					w.open:set(false)
					w.settle()
					w.scroll(touch)
					Verify.expect(w.list.CanvasPosition.Y > before):toBe(true)
					Verify.expect(w.page.CanvasPosition.Y):toBe(0)
				end
			)
		end
		verifyHarness:case(
			"shields block background presses and nested selection stays inside the top modal",
			function()
				local Facet = require("../src")
				local engines = require("./lib/native_engine")
				local Lute = require("../tools/vendor/verify/src/lute")
				local roots: { VerifyRoblox.Instance } = {}
				local engine, bridge = engines.new({
					layout = {
						roots = function()
							return roots
						end,
						viewport = function()
							return { X = 800, Y = 600 }
						end,
					},
				})
				local data: DataModel = engine.new("DataModel")
				local player: PlayerGui = engine.new("PlayerGui")
				local input: UserInputService = engine.new("UserInputService")
				local gui: GuiService = engine.new("GuiService")
				player.Parent, input.Parent, gui.Parent = data, data, data
				table.insert(roots, VerifyRoblox.assertInstance(player))
				local runtime = Facet.Roblox.createRuntime(engine)
				local Host = Facet.host(runtime)
				local UI = Facet.controls(runtime, {
					types = engine.types,
					motionLevel = "none",
					services = {
						UserInputService = input,
						GuiService = gui,
					},
				})
				local outer, inner = Compose.cell(false), Compose.cell(false)
				local presses = 0
				local outside: TextButton? = nil
				local scroller: ScrollingFrame? = nil
				local action: TextButton? = nil
				local childAction: TextButton? = nil
				local D2, E = engine.types.UDim2, engine.types.Enum
				local stop = runtime.mount(function()
					outside = Host.TextButton "Outside" {
						Size = D2.fromOffset(120, 44),
						Position = D2.fromOffset(10, 250),
						Activated = function()
							presses += 1
						end,
					}
					scroller = Host.ScrollingFrame "Background" {
						Size = D2.fromScale(1, 1),
						CanvasSize = D2.fromOffset(0, 1200),
						assert(outside),
					}
					return Host.ScreenGui {
						ScreenInsets = E.ScreenInsets.None,
						ZIndexBehavior = E.ZIndexBehavior.Sibling,
						assert(scroller),
						UI.Dialog {
							title = "Outer",
							isPresented = outer,
							closeButton = false,
							content = function()
								action = Host.TextButton "Action" { Size = D2.fromOffset(120, 44) }
								return assert(action)
							end,
						},
						UI.Dialog {
							title = "Inner",
							isPresented = inner,
							closeButton = false,
							content = function()
								childAction = Host.TextButton "ChildAction" { Size = D2.fromOffset(120, 44) }
								return assert(childAction)
							end,
						},
					}
				end, player)
				local backend = VerifyRoblox.inputHost.simulated(engine.environment, {
					playerGui = VerifyRoblox.assertInstance(player),
					inputService = VerifyRoblox.assertInstance(input),
					layout = assert(bridge.layout),
					inset = function()
						return { X = 0, Y = 0 }
					end,
					library = VerifyRoblox.reflectionSnapshot.library(Lute.fixture.load()),
					activationWindowSeconds = 0.5,
				})
				local function settle()
					for _ = 1, 3 do
						assert(bridge.layout).step()
						engine.heartbeat:Fire(1 / 60)
					end
				end
				local function press()
					backend.pointer({ x = 40, y = 270, button = "left", down = true })
					backend.pointer({ x = 40, y = 270, button = "left", down = false })
				end
				local function selectedName(): string
					local selected = gui.SelectedObject
					return if selected then selected.Name else "nil"
				end
				settle()
				press()
				Verify.expect(presses):toBe(1)
				engine.environment.poke(VerifyRoblox.assertInstance(input), "PreferredInput", E.PreferredInput.Gamepad)
				gui.SelectedObject = outside
				outer:set(true)
				settle()
				press()
				Verify.expect(presses):toBe(1)
				Verify.expect(assert(scroller).ScrollingEnabled):toBe(true)
				local late: TextButton = engine.new("TextButton")
				late.Size, late.Position, late.Parent = D2.fromOffset(120, 44), D2.fromOffset(10, 250), scroller
				local connection = late.Activated:Connect(function()
					presses += 1
				end)
				settle()
				press()
				Verify.expect(presses):toBe(1)
				for _, open in { inner, outer } do
					if open == inner then
						gui.SelectedObject = action
						inner:set(true)
						settle()
					end
					local target = if open == inner then assert(childAction) else assert(action)
					gui.SelectedObject = target
					for _, code in { "Up", "Down", "Left", "Right" } do
						backend.key({ code = code, down = true })
						backend.key({ code = code, down = false })
						Verify.expect(selectedName()):toBe(target.Name)
					end
					gui.SelectedObject = late
					Verify.expect(gui.SelectedObject == late):toBe(false)
					if open == inner then
						gui.SelectedObject = childAction
						inner:set(false)
						settle()
						Verify.expect(selectedName()):toBe("Action")
					end
				end
				outer:set(false)
				settle()
				Verify.expect(selectedName()):toBe("Outside")
				press()
				Verify.expect(presses):toBe(2)
				connection:Disconnect()
				backend.close()
				stop()
				runtime:dispose()
				bridge.close()
			end
		)
		verifyHarness:case("moves gamepad focus when the selected modal action becomes disabled", function()
			local open, enabled = Compose.cell(false), Compose.cell(true)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return UI.Dialog {
					isPresented = open,
					title = "Pages",
					closeButton = false,
					content = function(): Instance
						return Host.Frame {
							UI.Button "Previous" { label = "Previous" },
							UI.Button "Next" { label = "Next", enabled = enabled },
						}
					end,
				}
			end, { motionLevel = "none" })
			w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
			open:set(true)
			w.gui.SelectedObject = w.find("Next")
			enabled:set(false)
			Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Previous")
			w.stop()
		end)
		verifyHarness:case("a retained Sheet recovers selection after replacing its selected branch", {
			id = "native_modal_input::sheet-content-replacement-selection",
			run = function()
				for _, preferred in { "Gamepad", "KeyboardAndMouse" } do
					local open, detail = Compose.cell(false), Compose.cell(false)
					local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine)
						return Host.Frame {
							UI.Button "Opener" { label = "Open" },
							UI.Sheet {
								isPresented = open,
								title = "Equipment",
								placement = "center",
								content = function()
									return Host.Frame {
										Compose.show(detail, function()
											local control = UI.Button "Equip" { label = "Equip" }
											engine.environment.poke(
												VerifyRoblox.assertInstance(control),
												"AbsoluteSize",
												engine.types.Vector2.new(120, 44)
											)
											return control
										end, function()
											return UI.Button "Inspect" { label = "Inspect" }
										end),
									}
								end,
							},
						}
					end, { motionLevel = "none" })
					w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput[preferred])
					w.input.GetLastInputType = function()
						return w.Enum.UserInputType.Keyboard
					end
					w.gui.SelectedObject = w.find("Opener")
					open:set(true)
					w.advance(1 / 60, 3)
					w.size(w.find("Close"), 44, 44)
					local panel, removed = w.find("SheetPanel"), w.find("Inspect")
					w.gui.SelectedObject = removed
					detail:set(true)
					w.advance(1 / 60, 3)
					Verify.expect(removed.Parent):toBe(nil)
					Verify.expect(w.find("SheetPanel")):toBe(panel)
					Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Equip")
					Verify.expect(w.gui.SelectedObject:IsDescendantOf(panel)):toBe(true)
					Verify.expect(w.gui.SelectedObject.Selectable and w.gui.SelectedObject.Interactable):toBe(true)
					open:set(false)
					Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Opener")
					w.stop()
				end
			end,
		})
		verifyHarness:case("a retained Sheet recovers selection when an ancestor is detached", {
			id = "native_modal_input::sheet-content-ancestor-detached",
			run = function()
				local open = Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = open,
						title = "Equipment",
						placement = "center",
						content = function()
							return Host.Frame {
								Host.Frame "Branch" { UI.Button "Inspect" { label = "Inspect" } },
								UI.Button "Equip" { label = "Equip" },
							}
						end,
					}
				end, { motionLevel = "none" })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				open:set(true)
				w.advance(1 / 60, 3)
				local branch, removed, replacement = w.find("Branch"), w.find("Inspect"), w.find("Equip")
				w.size(replacement, 120, 44)
				w.gui.SelectedObject = removed
				branch.Parent = nil
				w.advance(1 / 60, 3)
				Verify.expect(removed.Parent):toBe(branch)
				Verify.expect(branch.Parent):toBe(nil)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Equip")
				w.stop()
			end,
		})
		verifyHarness:case("native fallback selection waits for replacement body bounds", {
			id = "native_modal_input::sheet-native-fallback-after-layout",
			run = function()
				local open, detail = Compose.cell(false), Compose.cell(false)
				local fallback = function() end
				local connection: RBXScriptConnection? = nil
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = open,
						title = "Equipment",
						placement = "center",
						content = function()
							return Host.Frame {
								Compose.show(detail, function()
									return UI.Button "Equip" { label = "Equip" }
								end, function()
									local branch = Host.Frame "Branch" { UI.Button "Inspect" { label = "Inspect" } }
									connection = branch:GetPropertyChangedSignal("Parent"):Connect(function()
										if branch.Parent == nil then
											fallback()
										end
									end)
									return branch
								end),
							}
						end,
					}
				end, { motionLevel = "none" })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				open:set(true)
				w.advance(1 / 60, 3)
				w.size(w.find("Close"), 44, 44)
				fallback = function()
					w.gui.SelectedObject = w.find("Close")
				end
				w.gui.SelectedObject = w.find("Inspect")
				detail:set(true)
				w.advance(1 / 60, 3)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Close")
				w.size(w.find("Equip"), 120, 44)
				w.advance(1 / 60, 3)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Equip")
				if connection then
					connection:Disconnect()
				end
				w.stop()
			end,
		})
		verifyHarness:case("a retained Sheet recovers through an empty body before replacement content arrives", {
			id = "native_modal_input::sheet-content-replacement-late",
			run = function()
				local open, ready = Compose.cell(false), Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = open,
						title = "Equipment",
						placement = "center",
						content = function()
							return Host.Frame {
								Compose.show(ready, function()
									return UI.Button "Equip" { label = "Equip" }
								end),
							}
						end,
					}
				end, { motionLevel = "none" })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				open:set(true)
				w.advance(1 / 60, 3)
				w.size(w.find("Close"), 44, 44)
				w.size(w.find("Equip"), 120, 44)
				w.gui.SelectedObject = w.find("Equip")
				ready:set(false)
				w.advance(1 / 60, 3)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Close")
				ready:set(true)
				w.advance(1 / 60, 3)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Close")
				w.size(w.find("Equip"), 120, 44)
				w.advance(1 / 60, 3)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Equip")
				w.stop()
			end,
		})
		verifyHarness:case("replacing parent Sheet content preserves nested focus and repairs its return", {
			id = "native_modal_input::sheet-content-replacement-nested",
			run = function()
				local open, child, detail = Compose.cell(false), Compose.cell(false), Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine)
					return Host.Frame {
						UI.Button "Opener" { label = "Open" },
						UI.Sheet {
							isPresented = open,
							title = "Equipment",
							placement = "center",
							content = function()
								return Host.Frame {
									Compose.show(detail, function()
										local control = UI.Button "Equip" { label = "Equip" }
										engine.environment.poke(
											VerifyRoblox.assertInstance(control),
											"AbsoluteSize",
											engine.types.Vector2.new(120, 44)
										)
										return control
									end, function()
										return UI.Button "Inspect" { label = "Inspect" }
									end),
									UI.Sheet {
										isPresented = child,
										title = "Details",
										content = function()
											return UI.Button "ChildAction" { label = "Continue" }
										end,
									},
								}
							end,
						},
					}
				end, { motionLevel = "none" })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				w.gui.SelectedObject = w.find("Opener")
				open:set(true)
				w.advance(1 / 60, 3)
				w.gui.SelectedObject = w.find("Inspect")
				child:set(true)
				w.advance(1 / 60, 3)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("ChildAction")
				detail:set(true)
				w.advance(1 / 60, 3)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("ChildAction")
				child:set(false)
				w.advance(1 / 60, 3)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Equip")
				open:set(false)
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Opener")
				w.stop()
			end,
		})
		verifyHarness:case("pointer input can clear valid modal selection while gamepad remains preferred", {
			id = "native_modal_input::pointer-clears-valid-selection",
			run = function()
				local open, detail = Compose.cell(false), Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet {
						isPresented = open,
						title = "Equipment",
						content = function()
							return Host.Frame {
								Compose.show(detail, function()
									return UI.Button "Inspect" { label = "Inspect" }
								end, function()
									return UI.Button "Equip" { label = "Equip" }
								end),
							}
						end,
					}
				end, { motionLevel = "none" })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				open:set(true)
				w.advance(1 / 60, 3)
				w.size(w.find("Equip"), 120, 44)
				w.gui.SelectedObject = w.find("Equip")
				w.input.LastInputTypeChanged:Fire(w.Enum.UserInputType.MouseMovement)
				w.advance(1 / 60, 3)
				Verify.expect(w.gui.SelectedObject):toBe(nil)
				detail:set(true)
				w.size(w.find("Inspect"), 120, 44)
				w.advance(1 / 60, 3)
				Verify.expect(w.gui.SelectedObject):toBe(nil)
				w.stop()
			end,
		})
		verifyHarness:case("a D-pad press enters a modal presented in the layer of a resting passive HUD", function()
			local open = Compose.cell(false)
			local resign: () -> () = function() end
			local state: () -> string = function(): string
				return "none"
			end
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				local hud = Host.ScreenGui {
					UI.Button "Map" { label = "Map" },
					UI.Dialog {
						isPresented = open,
						title = "Shop",
						closeButton = false,
						content = function(): Instance
							return Host.Frame { UI.Button "Buy" { label = "Buy" } }
						end,
					},
				}
				local responder = UI.responder(hud)
				resign = responder.resign
				state = function(): string
					return responder.state:peek()
				end
				return hud
			end, { motionLevel = "none" })
			w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
			open:set(true)
			resign()
			Verify.expect(state()):toBe("passive")
			Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("nil")
			w.input.InputBegan:Fire(
				{ UserInputType = w.Enum.UserInputType.Gamepad1, KeyCode = w.Enum.KeyCode.DPadDown },
				false
			)
			Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Buy")
			w.stop()
		end)
		verifyHarness:case("outside dismissal accepts pointer input while gamepad remains preferred", function()
			local open = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame { dialog(UI, Host, "About", open) }
			end)
			w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
			open:set(true)
			local target = w.find("DismissTarget")
			Verify.expect(target.Interactable):toBe(true)
			Verify.expect(target.Selectable):toBe(false)
			target.Activated:Fire({ UserInputType = w.Enum.UserInputType.Gamepad1 })
			Verify.expect(open:peek()):toBe(true)
			target.Activated:Fire({ UserInputType = w.Enum.UserInputType.MouseButton1 })
			Verify.expect(open:peek()):toBe(false)
			w.stop()
		end)
		verifyHarness:case("modal content mounting does not walk or mutate outside controls", function()
			local open = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				local children: { Instance } = {}
				for index = 1, 200 do
					table.insert(children, Host.TextButton { Name = `Outside{index}`, Selectable = true })
				end
				table.insert(children, dialog(UI, Host, "Many controls", open))
				return Host.Frame { table.unpack(children) }
			end, { motionLevel = "none" })
			local walks, writes = 0, 0
			local descendants = w.screen.GetDescendants
			w.screen.GetDescendants = function(screen)
				walks += 1
				return descendants(screen)
			end
			local children = w.screen.GetChildren
			w.screen.GetChildren = function(screen)
				walks += 1
				return children(screen)
			end
			local stop = w.engine.onWrite(function(node, property)
				if
					string.match(node.Name, "^Outside%d+$") and (property == "Interactable" or property == "Selectable")
				then
					writes += 1
				end
			end)
			open:set(true)
			Verify.expect(walks):toBe(0)
			Verify.expect(writes):toBe(0)
			for index = 1, 200 do
				local button = w.find(`Outside{index}`)
				Verify.expect(button.Interactable):toBe(true)
				Verify.expect(button.Selectable):toBe(true)
			end
			local parent = w.find("Outside1").Parent
			local late = w.engine.new("TextButton")
			local modal = modalOf(w, "Many controls")
			local before = walks
			late.Parent = parent
			Verify.expect(late.Interactable):toBe(true)
			Verify.expect(late.Selectable):toBe(true)
			for _ = 1, 200 do
				local label = w.engine.new("TextLabel")
				label.Parent = modal
			end
			Verify.expect(walks):toBe(before)
			open:set(false)
			for index = 1, 200 do
				local button = w.find(`Outside{index}`)
				Verify.expect(button.Interactable):toBe(true)
				Verify.expect(button.Selectable):toBe(true)
			end
			Verify.expect(late.Interactable):toBe(true)
			Verify.expect(late.Selectable):toBe(true)
			stop:Disconnect()
			w.stop()
		end)
		verifyHarness:case("nested modals preserve consumer changes to outside controls", function()
			local outer, inner = Compose.cell(false), Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame {
					Host.TextButton "Enabled" { Interactable = true, Selectable = true },
					Host.TextButton "Disabled" { Interactable = false, Selectable = false },
					dialog(UI, Host, "Outer", outer),
					dialog(UI, Host, "Inner", inner),
				}
			end, { motionLevel = "none" })
			local enabled, disabled = w.find("Enabled"), w.find("Disabled")
			outer:set(true)
			inner:set(true)
			outer:set(false)
			Verify.expect(enabled.Interactable):toBe(true)
			Verify.expect(enabled.Selectable):toBe(true)
			disabled.Interactable = true
			disabled.Selectable = true
			Verify.expect(disabled.Interactable):toBe(true)
			Verify.expect(disabled.Selectable):toBe(true)
			inner:set(false)
			Verify.expect(enabled.Interactable):toBe(true)
			Verify.expect(enabled.Selectable):toBe(true)
			Verify.expect(disabled.Interactable):toBe(true)
			Verify.expect(disabled.Selectable):toBe(true)
			disabled.Interactable = false
			disabled.Selectable = false
			outer:set(true)
			outer:set(false)
			Verify.expect(disabled.Interactable):toBe(false)
			Verify.expect(disabled.Selectable):toBe(false)
			w.stop()
		end)
		verifyHarness:case("deferred background changes remain authoritative after a modal closes", function()
			local open = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame {
					Host.TextButton "Outside" { Interactable = true, Selectable = true },
					dialog(UI, Host, "Deferred", open),
				}
			end, { motionLevel = "none" })
			local button = w.find("Outside")
			open:set(true)
			button.Interactable = false
			button.Selectable = false
			Verify.expect(button.Interactable):toBe(false)
			w.engine.propertyChanged(button, "Interactable"):Fire()
			w.engine.propertyChanged(button, "Selectable"):Fire()
			open:set(false)
			Verify.expect(button.Interactable):toBe(false)
			Verify.expect(button.Selectable):toBe(false)
			w.stop()
		end)
		verifyHarness:case("selection follows a control into the top modal and cannot return behind it", function()
			local outer, inner = Compose.cell(false), Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame {
					Host.TextButton "Move" { Interactable = true, Selectable = true },
					dialog(UI, Host, "Outer", outer),
					dialog(UI, Host, "Inner", inner),
				}
			end, { motionLevel = "none" })
			local button = w.find("Move")
			local parent = button.Parent
			w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
			outer:set(true)
			inner:set(true)
			w.gui.SelectedObject = button
			Verify.expect(w.gui.SelectedObject == button):toBe(false)
			button.Parent = nil
			button.Parent = modalOf(w, "Inner")
			Verify.expect(button.Interactable):toBe(true)
			Verify.expect(button.Selectable):toBe(true)
			w.gui.SelectedObject = button
			Verify.expect(w.gui.SelectedObject):toBe(button)
			button.Parent = nil
			button.Parent = parent
			Verify.expect(w.gui.SelectedObject == button):toBe(false)
			inner:set(false)
			w.gui.SelectedObject = button
			Verify.expect(w.gui.SelectedObject == button):toBe(false)
			outer:set(false)
			Verify.expect(button.Interactable):toBe(true)
			Verify.expect(button.Selectable):toBe(true)
			w.stop()
		end)
		verifyHarness:case("portal selection follows its anchor across modal ancestry changes", function()
			local open = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame {
					Host.Frame "Outside" {},
					UI.Dialog {
						isPresented = open,
						onPresentedChange = function(value: boolean)
							open:set(value)
						end,
						title = "Portal",
						content = function(): Instance
							local anchor: TextButton = Host.TextButton "PortalAnchor" { Selectable = true }
							return Host.Frame {
								anchor,
								UI.Callout {
									anchor = anchor,
									isPresented = true,
									content = function(): Instance
										return Host.TextButton "PortalAction" { Selectable = true }
									end,
									onRetire = function() end,
								},
							}
						end,
					},
				}
			end, { motionLevel = "none" })
			w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
			open:set(true)
			local anchor, action = w.find("PortalAnchor"), w.find("PortalAction")
			local parent = anchor.Parent
			Verify.expect(action ~= nil):toBe(true)
			Verify.expect(action.Interactable):toBe(true)
			Verify.expect(action.Selectable):toBe(true)
			w.gui.SelectedObject = action
			Verify.expect(w.gui.SelectedObject):toBe(action)
			anchor.Parent = w.find("Outside")
			Verify.expect(w.gui.SelectedObject == action):toBe(false)
			anchor.Parent = parent
			w.gui.SelectedObject = action
			Verify.expect(w.gui.SelectedObject):toBe(action)
			Verify.expect(action.Interactable):toBe(true)
			Verify.expect(action.Selectable):toBe(true)
			open:set(false)
			w.stop()
		end)
		verifyHarness:case("native touch controls stay hidden until the last modal releases its prior state", function()
			for _, enabled in { true, false } do
				local outer, inner = Compose.cell(false), Compose.cell(false)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, _engine, gui)
					gui.TouchControlsEnabled = enabled
					return Host.Frame { dialog(UI, Host, "Outer", outer), dialog(UI, Host, "Inner", inner) }
				end, { motionLevel = "none" })
				outer:set(true)
				Verify.expect(w.gui.TouchControlsEnabled):toBe(false)
				inner:set(true)
				outer:set(false)
				Verify.expect(w.gui.TouchControlsEnabled):toBe(false)
				inner:set(false)
				Verify.expect(w.gui.TouchControlsEnabled):toBe(enabled)
				outer:set(true)
				w.stop()
				Verify.expect(w.gui.TouchControlsEnabled):toBe(enabled)
			end
		end)
		verifyHarness:case("the modal root traps selection and its scrolling shield sinks input", {
			id = "native_modal_input::native modal: the scrim sinks input::the modal root and safe dismiss target sink input while the scrim stays passive",
			run = function()
				local open = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame { dialog(UI, Host, "About", open) }
				end)
				local modal = modalOf(w, "About")
				Verify.expect(modal.Active):toBe(true)
				Verify.expect(modal.SelectionGroup):toBe(true)
				for _, direction in { "Up", "Down", "Left", "Right" } do
					Verify.expect(
						w.engine.environment.propertyOf(
							VerifyRoblox.assertInstance(modal),
							"SelectionBehavior" .. direction
						)
					):toBe(w.Enum.SelectionBehavior.Stop)
				end
				local shield = overlay.find(modal, "Scrim")
				Verify.expect(shield.Active):toBe(true)
				Verify.expect(shield:IsA("ScrollingFrame")):toBe(true)
				Verify.expect(shield.CanvasSize):toBe(w.engine.types.UDim2.new())
				Verify.expect(shield.ScrollBarThickness):toBe(0)
				Verify.expect(overlay.find(modal, "DismissTarget").Active):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("the scrim covers asymmetric core UI insets and follows top bar changes", {
			id = "native_modal_input::native modal: the scrim sinks input::the scrim covers asymmetric core UI insets and follows top bar changes",
			run = function()
				local open = Compose.cell(false)
				local near, far
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine, gui)
					near, far = engine.types.Vector2.new(0, 87), engine.types.Vector2.new(0, 0)
					gui.GetGuiInset = function()
						return near, far
					end
					return Host.Frame { dialog(UI, Host, "About", open) }
				end)
				w.screen.ScreenInsets = w.Enum.ScreenInsets.CoreUISafeInsets
				w.screen.IgnoreGuiInset = false
				open:set(true)
				local scrim = w.find("Scrim")
				local target = w.find("DismissTarget")
				Verify.expect(target.Position):toBe(w.engine.types.UDim2.new())
				Verify.expect(target.Size):toBe(w.engine.types.UDim2.fromScale(1, 1))
				Verify.expect(scrim.Position):toBe(w.engine.types.UDim2.fromOffset(0, -87))
				Verify.expect(scrim.Size):toBe(w.engine.types.UDim2.new(1, 0, 1, 87))
				near, far = w.Vector2.new(12, 60), w.Vector2.new(8, 20)
				w.engine.environment.poke(w.gui, "TopbarInset", w.engine.types.Rect.new(0, 0, 100, 60))
				Verify.expect(scrim.Position):toBe(w.engine.types.UDim2.fromOffset(-12, -60))
				Verify.expect(scrim.Size):toBe(w.engine.types.UDim2.new(1, 20, 1, 80))
				Verify.expect(target.Position):toBe(w.engine.types.UDim2.new())
				Verify.expect(target.Size):toBe(w.engine.types.UDim2.fromScale(1, 1))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				Verify.expect(target.Interactable):toBe(true)
				Verify.expect(target.Selectable):toBe(false)
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Touch)
				Verify.expect(target.Interactable):toBe(true)
				w.stop()
			end,
		})
	end)
end
