--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")

	local function dialog(UI: any, Host: any, name: string, open: any): any
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

	local function modalOf(w: any, name: string): any
		for _, modal in w.findAll("DialogModal") do
			if overlay.find(modal, "Title").Text == name then
				return modal
			end
		end
		return nil
	end

	verifyHarness:suite("native modal: the scrim sinks input", function()
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
			w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
			open:set(true)
			w.gui.SelectedObject = w.find("Next")
			enabled:set(false)
			Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Previous")
			w.stop()
		end)
		verifyHarness:case("outside dismissal accepts pointer input while gamepad remains preferred", function()
			local open = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame({ dialog(UI, Host, "About", open) })
			end)
			w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
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
		verifyHarness:case("modal content mounting does not repeat the outside control walk", function()
			local open = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				local children: { Instance } = {}
				for index = 1, 200 do
					table.insert(children, Host.TextButton({ Name = `Outside{index}`, Selectable = true }))
				end
				table.insert(children, dialog(UI, Host, "Many controls", open))
				return Host.Frame({ table.unpack(children) })
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
			Verify.expect(walks <= 4):toBe(true)
			Verify.expect(writes):toBe(400)
			for index = 1, 200 do
				local button = w.find(`Outside{index}`)
				Verify.expect(button.Interactable):toBe(false)
				Verify.expect(button.Selectable):toBe(false)
			end
			local parent = w.find("Outside1").Parent
			local late = w.engine.new("TextButton")
			local modal = modalOf(w, "Many controls")
			local before = walks
			late.Parent = parent
			Verify.expect(late.Interactable):toBe(false)
			Verify.expect(late.Selectable):toBe(false)
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
		verifyHarness:case("nested modal leases restore each outside control's values", function()
			local outer, inner = Compose.cell(false), Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame({
					Host.TextButton "Enabled" { Interactable = true, Selectable = true },
					Host.TextButton "Disabled" { Interactable = false, Selectable = false },
					dialog(UI, Host, "Outer", outer),
					dialog(UI, Host, "Inner", inner),
				})
			end, { motionLevel = "none" })
			local enabled, disabled = w.find("Enabled"), w.find("Disabled")
			outer:set(true)
			inner:set(true)
			outer:set(false)
			Verify.expect(enabled.Interactable):toBe(false)
			Verify.expect(enabled.Selectable):toBe(false)
			disabled.Interactable = true
			disabled.Selectable = true
			Verify.expect(disabled.Interactable):toBe(false)
			Verify.expect(disabled.Selectable):toBe(false)
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
		verifyHarness:case("a deferred change signal for the modal's own write keeps the prior values", function()
			local open = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame({
					Host.TextButton "Outside" { Interactable = true, Selectable = true },
					dialog(UI, Host, "Deferred", open),
				})
			end, { motionLevel = "none" })
			local button = w.find("Outside")
			open:set(true)
			Verify.expect(button.Interactable):toBe(false)
			w.engine.propertyChanged(button, "Interactable"):Fire()
			w.engine.propertyChanged(button, "Selectable"):Fire()
			open:set(false)
			Verify.expect(button.Interactable):toBe(true)
			Verify.expect(button.Selectable):toBe(true)
			w.stop()
		end)
		verifyHarness:case("moving a leased control into the top modal releases every nested owner", function()
			local outer, inner = Compose.cell(false), Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame({
					Host.TextButton "Move" { Interactable = true, Selectable = true },
					dialog(UI, Host, "Outer", outer),
					dialog(UI, Host, "Inner", inner),
				})
			end, { motionLevel = "none" })
			local button = w.find("Move")
			local parent = button.Parent
			outer:set(true)
			inner:set(true)
			Verify.expect(button.Interactable):toBe(false)
			button.Parent = nil
			button.Parent = modalOf(w, "Inner")
			Verify.expect(button.Interactable):toBe(true)
			Verify.expect(button.Selectable):toBe(true)
			button.Parent = nil
			button.Parent = parent
			Verify.expect(button.Interactable):toBe(false)
			Verify.expect(button.Selectable):toBe(false)
			inner:set(false)
			Verify.expect(button.Interactable):toBe(false)
			outer:set(false)
			Verify.expect(button.Interactable):toBe(true)
			Verify.expect(button.Selectable):toBe(true)
			w.stop()
		end)
		verifyHarness:case("portal leases follow the anchor across modal ancestry changes", function()
			local open = Compose.cell(false)
			local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
				return Host.Frame({
					Host.Frame "Outside" {},
					UI.Dialog({
						isPresented = open,
						onPresentedChange = function(value: boolean)
							open:set(value)
						end,
						title = "Portal",
						content = function(): Instance
							local anchor = Host.TextButton "PortalAnchor" { Selectable = true }
							return Host.Frame({
								anchor :: Instance,
								UI.Callout({
									anchor = anchor,
									isPresented = true,
									content = function(): Instance
										return Host.TextButton "PortalAction" { Selectable = true }
									end,
									onRetire = function() end,
								}),
							})
						end,
					}),
				})
			end, { motionLevel = "none" })
			open:set(true)
			local anchor, action = w.find("PortalAnchor"), w.find("PortalAction")
			local parent = anchor.Parent
			Verify.expect(action ~= nil):toBe(true)
			Verify.expect(action.Interactable):toBe(true)
			Verify.expect(action.Selectable):toBe(true)
			anchor.Parent = w.find("Outside")
			Verify.expect(action.Interactable):toBe(false)
			Verify.expect(action.Selectable):toBe(false)
			anchor.Parent = parent
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
					return Host.Frame({ dialog(UI, Host, "Outer", outer), dialog(UI, Host, "Inner", inner) })
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
		verifyHarness:case("the modal root and safe dismiss target sink input while the scrim stays passive", {
			id = "native_modal_input::native modal: the scrim sinks input::the modal root and safe dismiss target sink input while the scrim stays passive",
			run = function()
				local open = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame({ dialog(UI, Host, "About", open) })
				end)
				local modal = modalOf(w, "About")
				Verify.expect(modal.Active):toBe(true)
				Verify.expect(overlay.find(modal, "Scrim").Active):toBe(false)
				Verify.expect(overlay.find(modal, "Scrim"):IsA("Frame")):toBe(true)
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
					return Host.Frame({ dialog(UI, Host, "About", open) })
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
				w.gui.TopbarInset = w.engine.types.Rect.new(0, 0, 100, 60)
				Verify.expect(scrim.Position):toBe(w.engine.types.UDim2.fromOffset(-12, -60))
				Verify.expect(scrim.Size):toBe(w.engine.types.UDim2.new(1, 20, 1, 80))
				Verify.expect(target.Position):toBe(w.engine.types.UDim2.new())
				Verify.expect(target.Size):toBe(w.engine.types.UDim2.fromScale(1, 1))
				w.input.PreferredInput = w.Enum.PreferredInput.Gamepad
				Verify.expect(target.Interactable):toBe(true)
				Verify.expect(target.Selectable):toBe(false)
				w.input.PreferredInput = w.Enum.PreferredInput.Touch
				Verify.expect(target.Interactable):toBe(true)
				w.stop()
			end,
		})
	end)
end
