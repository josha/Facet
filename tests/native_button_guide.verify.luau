--!strict
local Verify = require("../tools/vendor/verify/src/core")

return function(verifyHarness: Verify.Harness)
	type FacetControls = typeof(require("@repo/tools/typecheck/aliases").FacetControls)
	type RobloxHost = typeof(require("@repo/tools/typecheck/aliases").RobloxHost)
	type ButtonGuideProps = typeof(require("@repo/tools/typecheck/aliases").ButtonGuideProps)
	type ButtonGuideEntry = typeof(require("@repo/tools/typecheck/aliases").ButtonGuideEntry)

	local Compose = require("../src/vendor/compose/core")
	local overlay = require("./lib/overlay_world")
	local engines = require("./lib/native_engine")
	local VerifyRoblox = require("../tools/vendor/verify/src/roblox")
	type Engine = engines.Engine

	local function selectables(root: Instance): { string }
		local found: { string } = {}
		for _, node in { root, table.unpack(root:GetDescendants()) } do
			if node:IsA("GuiObject") and (node :: GuiObject).Selectable then
				table.insert(found, node:GetFullName())
			end
		end
		return found
	end

	local guideWorld = overlay.new

	local function labels(guide: Instance): string
		local shown: { { order: number, text: string } } = {}
		for _, node in guide:GetDescendants() do
			local entry = node :: GuiObject
			if node.Name == "Entry" and entry.Visible then
				table.insert(shown, { order = entry.LayoutOrder, text = overlay.find(node, "Label").Text })
			end
		end
		table.sort(shown, function(a, b)
			return a.order < b.order
		end)
		local words: { string } = {}
		for _, entry in shown do
			table.insert(words, entry.text)
		end
		return table.concat(words, " ")
	end

	local function boundAction(engine: Engine, name: string, key: string): InputAction
		local action: InputAction, binding: InputBinding = engine.new("InputAction"), engine.new("InputBinding")
		action.Name = name
		binding.KeyCode = ((engine.types.Enum.KeyCode :: unknown) :: { [string]: Enum.KeyCode })[key]
		engine.environment.poke((action :: unknown) :: VerifyRoblox.Instance, "PreferredBinding", binding)
		return action
	end

	verifyHarness:suite("native ButtonGuide", function()
		verifyHarness:case("shows for its input class, gamepad by default, and never on touch", {
			id = "native_button_guide::input-class",
			run = function()
				local w = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						entries = { { keys = { { "E" } }, label = "Buy" }, { keys = { { "Q" } }, label = "Back" } },
					}
				end)
				local guide = w.find("Guide")
				local P = w.Enum.PreferredInput
				w.engine.environment.poke(w.input, "PreferredInput", P.Gamepad)
				Verify.expect(guide.Visible):toBe(true)
				Verify.expect(labels(guide)):toBe("Buy Back")
				Verify.expect(overlay.find(guide, "Keys"):HasTag("facet-shortcut-hint-bare")):toBe(true)
				w.engine.environment.poke(w.input, "PreferredInput", P.KeyboardAndMouse)
				Verify.expect(guide.Visible):toBe(false)
				w.engine.environment.poke(w.input, "PreferredInput", P.Touch)
				Verify.expect(guide.Visible):toBe(false)
				w.stop()

				local both = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						inputs = { "Gamepad", "KeyboardAndMouse" },
						entries = { { keys = { { "E" } }, label = "Buy" } },
					}
				end)
				local shown = both.find("Guide")
				both.engine.environment.poke(both.input, "PreferredInput", P.KeyboardAndMouse)
				Verify.expect(shown.Visible):toBe(true)
				Verify.expect(overlay.find(shown, "Keys"):HasTag("facet-shortcut-hint-bare")):toBe(false)
				both.engine.environment.poke(both.input, "PreferredInput", P.Touch)
				Verify.expect(shown.Visible):toBe(false)
				both.engine.environment.poke(both.input, "PreferredInput", P.Gamepad)
				Verify.expect(shown.Visible):toBe(true)
				Verify.expect(overlay.find(shown, "Keys"):HasTag("facet-shortcut-hint-bare")):toBe(true)
				both.stop()
			end,
		})

		verifyHarness:case("mouse movement within keyboard and mouse never makes the guide flash", {
			id = "native_button_guide::no-flash",
			run = function()
				local w = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						entries = { { keys = { { "E" } }, label = "Buy" } },
					}
				end)
				local P = w.Enum.PreferredInput
				w.engine.environment.poke((w.input :: unknown) :: VerifyRoblox.Instance, "MouseEnabled", true)
				w.engine.environment.poke(w.input, "PreferredInput", P.Gamepad)
				local guide = w.find("Guide")
				local entry = overlay.find(guide, "Entry")
				Verify.expect(guide.Visible):toBe(true)
				local changes = 0
				guide:GetPropertyChangedSignal("Visible"):Connect(function()
					changes += 1
				end)
				for _ = 1, 3 do
					w.input.InputChanged:Fire({ UserInputType = w.Enum.UserInputType.MouseMovement }, false)
					w.input.InputBegan:Fire({ UserInputType = w.Enum.UserInputType.MouseButton1 }, false)
					w.advance(1 / 60)
				end
				Verify.expect(changes):toBe(0)
				Verify.expect(guide.Visible):toBe(true)
				Verify.expect(overlay.find(guide, "Entry")):toBe(entry)
				w.engine.environment.poke(w.input, "PreferredInput", P.KeyboardAndMouse)
				Verify.expect(guide.Visible):toBe(false)
				Verify.expect(changes):toBe(1)
				w.stop()
			end,
		})

		verifyHarness:case("refuses Touch and malformed entries", {
			id = "native_button_guide::refusals",
			run = function()
				local function buildWith(make: (Engine) -> unknown): () -> ()
					return function()
						local w = guideWorld(function(UI: FacetControls, _, engine: Engine)
							return UI.ButtonGuide(make(engine) :: ButtonGuideProps)
						end)
						w.stop()
					end
				end
				local function build(spec: unknown): () -> ()
					return buildWith(function()
						return spec
					end)
				end
				local entries = { { keys = { { "E" } }, label = "Buy" } }
				Verify.expect(build({ inputs = { "Touch" }, entries = entries })):toThrow("never shows on touch")
				Verify.expect(build({ inputs = { "Gamepad", "Touch" }, entries = entries }))
					:toThrow("never shows on touch")
				Verify.expect(build({ inputs = { "Mouse" }, entries = entries })):toThrow("inputs takes")
				Verify.expect(build({ inputs = {}, entries = entries })):toThrow("nonempty")
				Verify.expect(build({})):toThrow("entries is required")
				Verify.expect(build({ entries = { { label = "Buy" } } })):toThrow("one of action, keyCode or keys")
				Verify.expect(build({ entries = { { keys = { { "E" } }, keyCode = "E", label = "Buy" } } }))
					:toThrow("one of action, keyCode or keys")
				Verify.expect(build({ entries = { { keyCode = "ButtonA", label = "Buy" } } }))
					:toThrow("keyCode must be")
				Verify.expect(build({ entries = { { keyCode = {}, label = "Buy" } } })):toThrow("keyCode must be")
				Verify.expect(build({ entries = { { keys = { { "E" } } } } })):toThrow("needs a label")
				Verify.expect(build({ entries = { { action = {}, label = "Buy" } } })):toThrow("native InputAction")
				Verify.expect(build({ entries = entries, label = "Buy" })):toThrow("unknown option 'label'")
				Verify.expect(buildWith(function(engine: Engine)
					local buy = engine.new("InputAction")
					return { entries = { { action = buy, label = "Buy" }, { action = buy, label = "Sell" } } }
				end)):toThrow("an action appears twice; list each command once")
				local KeyCode = engines.types.Enum.KeyCode
				local A, L1, R1 = KeyCode.ButtonA, KeyCode.ButtonL1, KeyCode.ButtonR1
				Verify.expect(build({ entries = { { keyCode = A, label = "Buy" }, { keyCode = A, label = "Sell" } } }))
					:toThrow("a key appears twice; list each command once")
				local overlapping: { ButtonGuideEntry } =
					{ { keyCode = { L1, R1 }, label = "Tabs" }, { keyCode = R1, label = "Next" } }
				Verify.expect(build({ entries = overlapping })):toThrow("a key appears twice; list each command once")
				Verify.expect(build({
					entries = { { keys = { { "E" } }, label = "Use" }, { keys = { { "E" } }, label = "Use" } },
				})):toThrow("an entry appears twice")
			end,
		})

		verifyHarness:case("the buttonGuides app option hides every guide", {
			id = "native_button_guide::player-setting",
			run = function()
				local setting = Compose.cell(true)
				local w = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						entries = { { keys = { { "E" } }, label = "Buy" } },
					}
				end, { buttonGuides = setting })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				local guide = w.find("Guide")
				Verify.expect(guide.Visible):toBe(true)
				setting:set(false)
				Verify.expect(guide.Visible):toBe(false)
				setting:set(true)
				Verify.expect(guide.Visible):toBe(true)
				w.stop()

				local off = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						entries = { { keys = { { "E" } }, label = "Buy" } },
					}
				end, { buttonGuides = false })
				off.engine.environment.poke(off.input, "PreferredInput", off.Enum.PreferredInput.Gamepad)
				Verify.expect(off.find("Guide").Visible):toBe(false)
				off.stop()
			end,
		})

		verifyHarness:case("lists only enabled actions, follows the entries and hides when none is live", {
			id = "native_button_guide::live-entries",
			run = function()
				local buy: InputAction, back: InputAction
				local entries = Compose.cell({} :: { ButtonGuideEntry })
				local label = Compose.cell("Buy")
				local w = guideWorld(function(UI: FacetControls, _, engine: Engine)
					buy, back = boundAction(engine, "Buy", "ButtonA"), boundAction(engine, "Back", "ButtonB")
					entries:set({
						{ action = buy, label = label },
						{ action = back, label = "Back" },
						{ keys = { { "LB", "RB" } }, label = "Tabs" },
					})
					return UI.ButtonGuide "Guide" { entries = entries }
				end)
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				local guide = w.find("Guide")
				Verify.expect(labels(guide)):toBe("Buy Back Tabs")
				buy.Enabled = false
				Verify.expect(labels(guide)):toBe("Back Tabs")
				Verify.expect(guide.Visible):toBe(true)
				buy.Enabled = true
				label:set("Sell")
				Verify.expect(labels(guide)):toBe("Sell Back Tabs")
				entries:set({ { action = back, label = "Back" }, { action = buy, label = label } })
				Verify.expect(labels(guide)):toBe("Back Sell")
				buy.Enabled, back.Enabled = false, false
				Verify.expect(guide.Visible):toBe(false)
				back.Enabled = true
				Verify.expect(guide.Visible):toBe(true)
				entries:set({})
				Verify.expect(guide.Visible):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("an alert above the guide hides it; a guide inside the open surface stays", {
			id = "native_button_guide::modal-above",
			run = function()
				local alert = Compose.cell(false)
				local w = guideWorld(function(UI: FacetControls, Host: RobloxHost)
					return Host.Frame "Scene" {
						UI.ButtonGuide "HudGuide" { entries = { { keys = { { "Y" } }, label = "Map" } } } :: unknown,
						UI.Alert {
							isPresented = alert,
							title = "Leave the race?",
							actions = { { id = "Stay", label = "Stay", role = "cancel" :: "cancel" } },
						},
					}
				end, { motionLevel = "none" })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				local guide = w.find("HudGuide")
				Verify.expect(guide.Visible):toBe(true)
				alert:set(true)
				w.advance(1 / 60, 3)
				Verify.expect(guide.Visible):toBe(false)
				alert:set(false)
				w.advance(1, 10)
				Verify.expect(guide.Visible):toBe(true)
				w.stop()
			end,
		})

		verifyHarness:case("nothing in a guide is selectable or active", {
			id = "native_button_guide::readout",
			run = function()
				local w = guideWorld(function(UI: FacetControls, _, engine: Engine)
					local entries: { ButtonGuideEntry } = {
						{ action = boundAction(engine, "Buy", "ButtonA"), label = "Buy" },
						{ keys = { { "Esc" } }, label = "Back" },
					}
					return UI.ButtonGuide "Guide" {
						inputs = { "Gamepad", "KeyboardAndMouse" },
						Selectable = true,
						entries = entries,
					}
				end)
				for _, input in { "Gamepad", "KeyboardAndMouse" } do
					w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput[input])
					local guide = w.find("Guide")
					Verify.expect(guide.Visible):toBe(true)
					Verify.expect(guide.Active):toBe(false)
					Verify.expect(table.concat(selectables(guide), ", ")):toBe("")
				end
				w.stop()
			end,
		})

		verifyHarness:case("a Sheet guide sits on the bottom edge outside the scroller and is never a stop", {
			id = "native_button_guide::sheet-slot",
			run = function()
				local shown = Compose.cell(false)
				local buy: InputAction
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost, engine: Engine)
					buy = boundAction(engine, "Buy", "ButtonA")
					local guideEntries: { ButtonGuideEntry } =
						{ { action = buy, label = "Buy" }, { keys = { { "LB" } }, label = "Tabs" } }
					return UI.Sheet "Shop" {
						isPresented = shown,
						placement = "center",
						closeButton = true,
						title = "Shop",
						content = function(): Instance
							return Host.Frame "Shelf" {
								UI.Button "Blade" { label = "Blade" } :: unknown,
								UI.Button "Wheels" { label = "Wheels" },
							}
						end,
						actions = { { id = "Done", label = "Done", onActivate = function() end } },
						guide = {
							entries = guideEntries,
						},
					}
				end, { motionLevel = "none" })
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				shown:set(true)
				w.advance(1 / 60, 3)
				local guide, room = w.find("ButtonGuide"), w.find("Room")
				local region = guide.Parent
				Verify.expect(region.Name):toBe("Guide")
				Verify.expect(region.Parent):toBe(room.Parent)
				Verify.expect((region:IsDescendantOf(room))):toBe(false)
				Verify.expect(region:FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment)
					:toBe(w.Enum.HorizontalAlignment.Right)
				Verify.expect(region.Visible):toBe(true)
				w.size(region, 500, 40)
				w.advance(1 / 60)
				Verify.expect(region.AnchorPoint.Y):toBe(1)
				Verify.expect(region.Position.Y.Offset):toBe(room.Position.Y.Offset + room.Size.Y.Offset + 8 + 40)
				Verify.expect(guide.Visible):toBe(true)
				Verify.expect(table.concat(selectables(region), ", ")):toBe("")
				Verify.expect(if w.gui.SelectedObject then w.gui.SelectedObject.Name else "nil"):toBe("Blade")
				for _, key in { "DPadDown", "DPadDown", "DPadDown", "DPadUp", "DPadRight" } do
					w.input.InputBegan:Fire({ KeyCode = w.Enum.KeyCode[key] })
					w.advance(1 / 10, 3)
					local selected = w.gui.SelectedObject
					Verify.expect(selected == nil or not selected:IsDescendantOf(region)):toBe(true)
				end
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.KeyboardAndMouse)
				Verify.expect(region.Visible):toBe(false)
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				Verify.expect(region.Visible):toBe(true)
				buy.Enabled = false
				Verify.expect(labels(guide)):toBe("Tabs")
				w.stop()
			end,
		})

		verifyHarness:case("guideAlignment start puts the Sheet guide on the leading edge", {
			id = "native_button_guide::sheet-alignment",
			run = function()
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet "Shop" {
						isPresented = Compose.cell(true),
						title = "Shop",
						content = function(): Instance
							return Host.TextLabel "Copy" { Text = "Pick a part." }
						end,
						guide = { entries = { { keys = { { "LB" } }, label = "Tabs" } } },
						guideAlignment = "start",
					}
				end, { motionLevel = "none" })
				Verify.expect(w.find("Guide"):FindFirstChildWhichIsA("UIListLayout").HorizontalAlignment)
					:toBe(w.Enum.HorizontalAlignment.Left)
				w.stop()
				local failures: { string } = {}
				overlay
					.new(function(UI: FacetControls, Host: RobloxHost)
						return UI.Sheet {
							isPresented = Compose.cell(true),
							content = function(): Instance
								return Host.Frame {}
							end,
							guide = { entries = {} },
							guideAlignment = ("middle" :: unknown) :: "start",
						}
					end, {
						onError = function(failure: unknown)
							table.insert(failures, tostring(failure))
						end,
					})
					.stop()
				Verify.expect(#failures):toBe(1)
				Verify.expect((string.find(failures[1], "guideAlignment must be start or end", 1, true)) ~= nil)
					:toBe(true)
			end,
		})

		verifyHarness:case("an action entry shows only while the device has a binding for it", {
			id = "native_button_guide::binding",
			run = function()
				local buy: InputAction, binding: InputBinding
				local w = guideWorld(function(UI: FacetControls, _, engine: Engine)
					buy, binding = engine.new("InputAction"), engine.new("InputBinding")
					binding.KeyCode = engine.types.Enum.KeyCode.ButtonA
					return UI.ButtonGuide "Guide" { entries = { { action = buy, label = "Buy" } } }
				end)
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				local guide = w.find("Guide")
				Verify.expect(guide.Visible):toBe(false)
				Verify.expect(labels(guide)):toBe("")
				w.engine.environment.poke((buy :: unknown) :: VerifyRoblox.Instance, "PreferredBinding", binding)
				Verify.expect(guide.Visible):toBe(true)
				Verify.expect(labels(guide)):toBe("Buy")
				w.engine.environment.poke((buy :: unknown) :: VerifyRoblox.Instance, "PreferredBinding", nil)
				Verify.expect(guide.Visible):toBe(false)
				w.stop()
			end,
		})

		verifyHarness:case("a keyCode entry draws the platform glyph, else the platform key name", {
			id = "native_button_guide::key-code",
			run = function()
				local entries = Compose.cell({} :: { ButtonGuideEntry })
				local w = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" { entries = entries }
				end)
				w.engine.environment.fakeOn(
					w.input,
					"GetImageForKeyCode",
					function(_self: unknown, code: EnumItem): string
						return if code.Name == "ButtonA" then "rbxasset://glyph/cross.png" else ""
					end
				)
				w.engine.environment.fakeOn(
					w.input,
					"GetStringForKeyCode",
					function(_self: unknown, code: EnumItem): string
						return if code.Name == "ButtonL1" then "L1" elseif code.Name == "ButtonR1" then "R1" else ""
					end
				)
				local KeyCode = w.Enum.KeyCode
				entries:set({
					{ keyCode = KeyCode.ButtonA, label = "Buy" },
					{ keyCode = { KeyCode.ButtonL1, KeyCode.ButtonR1 }, label = "Tabs" },
				})
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				local guide = w.find("Guide")
				Verify.expect(labels(guide)):toBe("Buy Tabs")
				local entryNodes: { GuiObject } = {}
				for _, node in guide:GetDescendants() do
					if node.Name == "Entry" then
						table.insert(entryNodes, node :: GuiObject)
					end
				end
				table.sort(entryNodes, function(a, b)
					return a.LayoutOrder < b.LayoutOrder
				end)
				local buy, tabs = entryNodes[1], entryNodes[2]
				Verify.expect(overlay.find(buy, "Glyph").Image):toBe("rbxasset://glyph/cross.png")
				local keys = overlay.find(tabs, "Keys")
				Verify.expect(keys:HasTag("facet-shortcut-hint-bare")):toBe(true)
				local names: { string } = {}
				for _, node in keys:GetDescendants() do
					if node.Name == "Key" then
						table.insert(names, node.Text)
					end
				end
				table.sort(names)
				Verify.expect(table.concat(names, " ")):toBe("L1 R1")
				w.stop()
			end,
		})

		verifyHarness:case("recomputed entries keep their hints when the commands are the same", {
			id = "native_button_guide::stable-keys",
			run = function()
				local tick = Compose.cell(0)
				local w = guideWorld(function(UI: FacetControls)
					return UI.ButtonGuide "Guide" {
						entries = function(use)
							use(tick)
							return {
								{ keys = { { "E" } }, label = "Use" },
								{ keyCode = engines.types.Enum.KeyCode.ButtonY, label = "Map" },
							}
						end,
					}
				end)
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				local guide = w.find("Guide")
				local before: { Instance } = {}
				for _, node in guide:GetDescendants() do
					if node.Name == "Entry" then
						table.insert(before, node)
					end
				end
				Verify.expect(#before):toBe(2)
				tick:set(1)
				for _, node in before do
					Verify.expect(node:IsDescendantOf(guide)):toBe(true)
				end
				w.stop()
			end,
		})

		verifyHarness:case("a hidden Sheet guide gives its pinned room back to the body", {
			id = "native_button_guide::sheet-room",
			run = function()
				local shown = Compose.cell(true)
				local w = overlay.new(function(UI: FacetControls, Host: RobloxHost)
					return UI.Sheet "Shop" {
						isPresented = shown,
						detent = "medium",
						title = "Shop",
						content = function(): Instance
							return Host.TextLabel "Copy" { Text = "Pick a part." }
						end,
						guide = { entries = { { keys = { { "LB" } }, label = "Tabs" } } },
					}
				end, { motionLevel = "none" })
				w.engine.environment.poke(w.find("Modal"), "AbsoluteSize", w.Vector2.new(800, 600))
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.Gamepad)
				w.advance(1 / 300, 2)
				local region, body = w.find("Guide"), w.find("SheetContent")
				w.size(w.find("Header"), 500, 44)
				w.size(region, 500, 40)
				w.advance(1 / 60)
				local withGuide = body.Size.Y.Offset
				w.engine.environment.poke(w.input, "PreferredInput", w.Enum.PreferredInput.KeyboardAndMouse)
				w.advance(1 / 60)
				Verify.expect(region.Visible):toBe(false)
				Verify.expect(body.Size.Y.Offset):toBe(withGuide + 40 + 8)
				w.stop()
			end,
		})
	end)
end
